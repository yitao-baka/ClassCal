/// 课前提醒设置。
///
/// 这一页比别的设置页啰嗦，是因为**这块功能本来就不可靠**：它依赖三个用户
/// 能在系统里随时收回的授权（通知、精确闹钟、后台定位），还依赖厂商的
/// 后台策略放行。所以页面把「现在到底能不能响」拆成看得见的三行状态，
/// 而不是给一个开关就假装万事大吉。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/native_sync.dart';
import '../../app/settings_providers.dart';
import '../../core/platform/reminder_scheduler.dart';
import '../../core/reminder/reminder_plan.dart';
import '../../core/settings/app_settings.dart';
import '../../core/time/periods.dart';
import '../../data/db/database.dart';
import 'oem_guide_page.dart';
import 'reminder_scope.dart';

void showReminderPage(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReminderPage()),
    );

/// 打开某一个日程的提醒页。
void showSetReminderPage(BuildContext context, int setId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReminderPage(setId: setId)),
    );

/// 提醒设置页。**一页两用**：`setId` 为 null 就是全局默认，非空就是某个日程。
///
/// 之所以是一页而不是两个页面：页体的那四节（提前多久 / 定位门控 / 通知自动清除 /
/// 重复提醒）在两种模式下**一模一样**，都只认一个 [ReminderScope]。抄两遍的话，
/// 以后每加一项设置都要记得改两处，而漏掉一处的表现是「这个选项在日程页里没有」——
/// 那种缺失没人会立刻发现。
///
/// 差别只有两处：日程页顶部多一个「跟随全局默认」开关，以及下面几节**不出现**。
class ReminderPage extends ConsumerStatefulWidget {
  const ReminderPage({super.key, this.setId});

  /// null = 全局默认。
  final int? setId;

  @override
  ConsumerState<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends ConsumerState<ReminderPage> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 用户去系统设置里改完权限回来，得重新查一遍 —— 那是最常见的操作路径，
    // 不重查的话页面会一直显示旧状态，用户只能退出重进。
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(reminderCapabilitiesProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final caps = ref.watch(reminderCapabilitiesProvider);
    final scope = ReminderScope(
      ref: ref,
      setId: widget.setId,
      settings: settings,
    );

    return Scaffold(
      appBar: AppBar(title: Text(_title(context))),
      body: widget.setId == null
          ? _globalBody(context, settings, notifier, caps, scope)
          : _setBody(context, settings, scope),
    );
  }

  String _title(BuildContext context) {
    final id = widget.setId;
    if (id == null) return '课前提醒';
    final row = ref
        .watch(tabRowsProvider)
        .value
        ?.where((t) => t.id == id)
        .firstOrNull;
    // 日程已经被删掉时页面还开着 —— 说清是「哪个日程的设置」比给个空标题好，
    // 用户至少知道自己在看一份已经没有主人的设置。
    return row?.name ?? '提醒设置';
  }

  /// 全局默认页。这一页的每一项都是「默认」—— 单个日程可以覆盖其中几项。
  Widget _globalBody(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
    AsyncValue<ReminderCapabilities> caps,
    ReminderScope scope,
  ) {
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('开启课前提醒'),
          subtitle: const Text('按每节课的提前量提醒；单门课可以在「编辑课程」里单独设定'),
          value: settings.remindersEnabled,
          onChanged: (v) =>
              notifier.update((s) => s.copyWith(remindersEnabled: v)),
        ),
        if (settings.remindersEnabled) ...[
          const Divider(),
          _section(context, '提前多久'),
          _LeadPicker(scope: scope),
          const Divider(),
          _section(context, '定位门控'),
          _GateTile(scope: scope),
          const Divider(),
          _section(context, '地点'),
          _PlacesList(settings: settings, notifier: notifier),
          const Divider(),
          _section(context, '通知自动清除'),
          _TimeoutPicker(scope: scope),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              '上课铃响之后，通知栏里那条「还有 15 分钟上课」就只是噪音了。'
              '设一个时间让它自己消失，省得上午的提醒堆到晚上还挂着。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
          _section(context, '重复提醒'),
          _RepeatTile(scope: scope),
          const Divider(),
          _section(context, '按日程分别设置'),
          _PerSetList(settings: settings),
          const Divider(),
          _section(context, '系统权限'),
          _PermissionCards(caps: caps),
          const Divider(),
          _section(context, '检查与排查'),
          _ReminderStatusCard(caps: caps),
          _TestReminderTile(caps: caps),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('后台限制：让系统别杀它'),
            subtitle: const Text('小米、华为、OPPO、vivo 这些 ROM 会拦掉后台闹钟'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showOemGuidePage(context),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              '提醒由系统闹钟触发，不需要 App 一直开着。但关了通知、撤了精确闹钟'
              '权限、或者厂商把后台限制打开之后，它就不会响 —— 上面三行状态'
              '就是用来确认这些的。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  /// 某一个日程的提醒页。
  ///
  /// **只剩这四节**，三节全局的（地点 / 系统权限 / 检查与排查）不出现：
  ///
  /// * **地点**是「我到过哪些地方」这个事实，全局唯一一份。摆在这里要么是假的
  ///   （点了改不动），要么是**诱惑用户在每个日程里重录同一栋楼**。
  /// * **系统权限**和**检查与排查**是**设备级**的，和日程无关。放进来会让用户
  ///   以为「这个日程没权限、那个有」。而且在这里点「试一条提醒」，测出来的是
  ///   哪一套参数都说不清。
  Widget _setBody(
    BuildContext context,
    AppSettings settings,
    ReminderScope scope,
  ) {
    final following = scope.following;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        SwitchListTile(
          title: const Text('跟随全局默认'),
          subtitle: const Text('关掉之后这个日程用自己的提醒设置'),
          value: following,
          onChanged: (v) => scope.setFollowing(v),
        ),
        if (following)
          // **画只读摘要，而不是把全局值置灰摆在这里。**
          //
          // 置灰的那一套和自定义模式下那组控件长得一模一样，用户会把它当成
          // 「这个日程自己的值」；而且它会**过期** —— 全局值一改，这一页没重建
          // 就还显示旧数。这行摘要读的是**当下**的全局值，措辞（「用全局设置：…」）
          // 也明说了它不属于这个日程。
          //
          // 藏着而不是置灰，和这个 App 里两处既有做法一致（course_editor /
          // 提醒页关掉总开关时的那一片）。
          //
          // **这一行同时是唯一的回路**：首页菜单可以直达某一个日程的提醒页
          // （「本日程的提醒」），从那条路进来的人没经过全局页，而全局默认
          // （提前量、门控模式的那份默认值）只能在全局页改。没有这个 `onTap`，
          // 他要么原路退回去一路点，要么根本不知道还有那么一页。
          InkWell(
            onTap: () => showReminderPage(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 15, color: scheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '用全局设置：${reminderSummary(SetReminderSettings.fromGlobal(settings))}',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: scheme.outline),
                ],
              ),
            ),
          )
        else ...[
          // 「这个日程整个不提醒」。
          //
          // 这一档**算法一直支持、界面一直产不出来**：`SetReminderSettings.
          // remindersEnabled` 是三层与里日程那一层（见 `buildReminderPlan`），
          // 但块的来源是 `setFollowing(false)` → `fromGlobal`，而能走到这一页
          // 就说明全局总闸开着 —— 于是它事实上恒为 true。用户要的是
          // 「全局开着，但「辅修」这个日程一条都别响」。
          //
          // 关掉之后下面四节**藏起来**而不是置灰：一份改了不会生效的设置比
          // 看不到更糟。形状和全局页那个总开关下面一模一样。
          SwitchListTile(
            title: const Text('开启这个日程的提醒'),
            subtitle: const Text('关掉之后这个日程一条提醒都不排；其它日程不受影响'),
            value: scope.values.remindersEnabled,
            onChanged: (v) => scope.write((s) => s.copyWith(remindersEnabled: v)),
          ),
          if (scope.values.remindersEnabled) ...[
            const Divider(),
            _section(context, '提前多久'),
            _LeadPicker(scope: scope),
            const Divider(),
            _section(context, '定位门控'),
            _GateTile(scope: scope),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                // 不写这一句的话，用户会以为日程页漏了「地点」那一节。
                '门控用的地点是全局那一份（在「课前提醒」主页里改），'
                '这里只管这个日程用什么模式、判定多远。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const Divider(),
            _section(context, '通知自动清除'),
            _TimeoutPicker(scope: scope),
            const Divider(),
            _section(context, '重复提醒'),
            _RepeatTile(scope: scope),
            const SizedBox(height: 24),
          ],
        ],
      ],
    );
  }
}

Widget _section(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
  child: Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.primary,
    ),
  ),
);

/// 「按日程分别设置」那一节。
///
/// 只列**真正的日程**，总览不在这里 —— 它是同一批事件的另一个视图，给它一套
/// 提醒会让同一节课被两个日程各提醒一次。这一条是用户在需求里钉死的：
/// 「提醒跟着事件所属的日程」。
///
/// 摘要说**实际会发生什么**（哪怕是跟随全局时），而不是「跟随全局」四个字：
/// 前者能让人一眼看出改没改成功，后者还得点进去才知道。
class _PerSetList extends ConsumerWidget {
  const _PerSetList({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(tabRowsProvider).value ?? const <CalendarSet>[];

    if (rows.isEmpty) {
      return const ListTile(
        title: Text('还没有日程'),
        subtitle: Text('导入一份课表之后，每个日程都能在这里单独配提醒'),
      );
    }

    final global = SetReminderSettings.fromGlobal(settings);
    return Column(
      children: [
        for (final r in rows)
          ListTile(
            leading: const Icon(Icons.alarm_on),
            title: Text(r.name),
            subtitle: Text(
              switch (settings.remindersFor(r.id)) {
                null => '跟随全局：${reminderSummary(global)}',
                // 被关掉的那个日程**不能**继续写「提前 30 分钟 · 已在教室则静音」——
                // 那看起来是在正常提醒，实际一条都不排。这个功能的失败方式一直是
                // 安静的，所以这一行必须说实话。
                final b when !b.remindersEnabled => '这个日程的提醒已关闭',
                final b => reminderSummary(b),
              },
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showSetReminderPage(context, r.id),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 提前量
// ---------------------------------------------------------------------------

/// 常见的几档 + 自定义。
///
/// 用 chips 而不是滑块：提前量是个「15 分钟」这种口头上的整数，
/// 滑块只会让人在 13 和 17 之间犹豫。
class _LeadPicker extends StatelessWidget {
  const _LeadPicker({required this.scope});

  final ReminderScope scope;

  static const List<int> _presets = [5, 10, 15, 20, 30, 60];

  @override
  Widget build(BuildContext context) {
    final current = scope.values.defaultLeadMinutes;
    final isPreset = _presets.contains(current);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in _presets)
            ChoiceChip(
              label: Text('$m 分钟'),
              selected: current == m,
              onSelected: (_) =>
                  scope.write((v) => v.copyWith(defaultLeadMinutes: m)),
            ),
          ChoiceChip(
            label: Text(isPreset ? '自定义…' : '$current 分钟'),
            selected: !isPreset,
            onSelected: (_) => _pickCustom(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final controller = TextEditingController(
      text: scope.values.defaultLeadMinutes.toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义提前量'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '提前分钟数',
            suffixText: '分钟',
            helperText: '0 表示正好在上课时提醒',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (value == null) return;
    // 夹到合法区间再存 —— 输入框里能敲出任何东西，而一个负的提前量意味着
    // 提醒排在下课之后。
    scope.write(
      (v) => v.copyWith(
        defaultLeadMinutes: value.clamp(0, AppSettings.kMaxLeadMinutes),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 定位门控
// ---------------------------------------------------------------------------

/// 「人已经在教室附近」时怎么办 —— 三选一，外加判定半径。
///
/// 用三个带说明的 `RadioListTile` 而不是一个开关：这三态的差别不在名字上
/// （「静音」和「不提醒」听起来都很像「不响」），而在**你到底还会不会看到这条
/// 提醒**。说明文字必须跟着每一项走，否则用户得靠试才知道区别 —— 而这件事
/// 一天只会试一次。
class _GateTile extends ConsumerStatefulWidget {
  const _GateTile({required this.scope});

  final ReminderScope scope;

  @override
  ConsumerState<_GateTile> createState() => _GateTileState();
}

class _GateTileState extends ConsumerState<_GateTile> {
  static const Map<NearbyMode, (String, String)> _labels = {
    NearbyMode.remind: ('照常提醒', '不做门控：到点就正常弹通知、正常响'),
    NearbyMode.skip: ('不提醒', '判断你已经在教室附近就不弹了。最安静，但你也看不到这条提醒'),
    NearbyMode.silent: (
      '提醒但静音',
      '照常弹出通知，只是没有铃声和振动 —— 已经在教学楼了，想扫一眼确认今天这节是不是换了教室',
    ),
  };

  /// 拖动过程中的临时值；null = 没在拖，读设置里那个数。
  ///
  /// 有这个字段是因为原来 `onChanged` 每一跳都 `scope.write` —— 一次设置写入
  /// 就是一次 `settings.json` 落盘，还有一次（`ClassCalApp` 收窄之前的）全 App
  /// 重建。拖动本该只是画得动，不该每跳都写盘。
  int? _dragMeters;

  @override
  void didUpdateWidget(covariant _GateTile old) {
    super.didUpdateWidget(old);
    // 写下去的那一跳走完、设置里真的是这个数了，就把临时值交还给设置 ——
    // 不然滑块会一直停在一个用户在别处改不动的数上。
    //
    // **不能在 `onChangeEnd` 里直接清**：那个回调里 `widget.scope` 还是旧的
    // （持有上一帧的 `settings` 快照），清掉会让滑块闪回旧值一帧再跳到新值。
    final value = widget.scope.values.gateRadiusMeters;
    if (_dragMeters != null && value == _dragMeters) _dragMeters = null;
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final caps = ref.watch(reminderCapabilitiesProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final mode = scope.values.nearbyMode;
    final meters = _dragMeters ?? scope.values.gateRadiusMeters;

    // 选中态和回调挂在 `RadioGroup` 上而不是每个 `RadioListTile` 上：
    // 后者在 3.32 之后已经废弃。三种模式各写一次 `groupValue`/`onChanged`
    // 也确实是重复 —— 它们本来就是一组互斥选项。
    return RadioGroup<NearbyMode>(
      groupValue: mode,
      // 关掉提醒总开关时这一整块根本不显示，所以这里不必再判一次。
      onChanged: (v) => scope.write((s) => s.copyWith(nearbyMode: v)),
      child: Column(
        children: [
          for (final entry in _labels.entries)
            RadioListTile<NearbyMode>(
              value: entry.key,
              title: Text(entry.value.$1),
              subtitle: Text(entry.value.$2),
            ),
          if (mode != NearbyMode.remind) ...[
            if (caps != null && caps.location != LocationPermission.always)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 15,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        caps.location == LocationPermission.foregroundOnly
                            ? '现在只给了「使用应用时」的位置权限。提醒响的时候 App 在后台，'
                                  '这种权限取不到位置，门控会一直走降级路径。'
                            : '还没给位置权限，门控暂时不会生效。',
                        style: TextStyle(fontSize: 12, color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ListTile(
              title: const Text('判定半径'),
              subtitle: Slider(
                // 滑块的范围比 AppSettings 允许的窄：1000 米以上的半径等于
                // 「整个校区」，没人真的想要那个，但配置文件里留着它是无害的，
                // 所以只是滑不到，而不是被判非法。
                value: meters.toDouble().clamp(50, 500),
                min: 50,
                max: 500,
                divisions: 9,
                label: '$meters 米',
                onChanged: (v) => setState(() => _dragMeters = v.round()),
                onChangeEnd: (v) =>
                    scope.write((s) => s.copyWith(gateRadiusMeters: v.round())),
              ),
              trailing: Text(
                '$meters 米',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                '只有课程地点能对上下面某个地点时才门控；对不上就照常提醒 —— '
                '漏一次提醒的代价比多响一次大得多。',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 通知自动清除
// ---------------------------------------------------------------------------

/// 提醒弹出后多久自己消失。
///
/// 和提前量一样用 chips：这是个「半小时」「一小时」量级的整数，滑块只会让人
/// 在 27 和 33 之间犹豫。
class _TimeoutPicker extends StatelessWidget {
  const _TimeoutPicker({required this.scope});

  final ReminderScope scope;

  /// `1` 在里面是有用的：配合重复提醒时，人到了教室、按下按钮之前那一条
  /// 只该占通知栏一分钟。
  static const List<int> _presets = [0, 1, 10, 30, 60];

  /// `0` 是一个真实的取值（不自动清除），不是「没选」。所以标签不能靠
  /// `'$m 分钟'` 拼出来 —— 「0 分钟」看起来像立刻消失，正好说反。
  static String label(int minutes) => minutes <= 0
      ? '不自动清除'
      : (minutes % 60 == 0 ? '${minutes ~/ 60} 小时' : '$minutes 分钟');

  @override
  Widget build(BuildContext context) {
    final current = scope.values.notificationTimeoutMinutes;
    final isPreset = _presets.contains(current);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in _presets)
            ChoiceChip(
              label: Text(label(m)),
              selected: current == m,
              onSelected: (_) => scope.write(
                (s) => s.copyWith(notificationTimeoutMinutes: m),
              ),
            ),
          ChoiceChip(
            label: Text(isPreset ? '自定义…' : label(current)),
            selected: !isPreset,
            onSelected: (_) => _pickCustom(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final controller = TextEditingController(
      text: scope.values.notificationTimeoutMinutes.toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义清除时间'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '弹出后多久消失',
            suffixText: '分钟',
            helperText: '0 表示不自动清除',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (value == null) return;
    scope.write(
      (s) => s.copyWith(
        notificationTimeoutMinutes: value.clamp(
          0,
          AppSettings.kMaxTimeoutMinutes,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 重复提醒
// ---------------------------------------------------------------------------

/// 一条提醒反复弹，直到人真的到了教室，或者已经上课。
///
/// 和前面几项不同，这一项**会主动打扰用户**，所以说明文字要把「什么时候停」
/// 写清楚 —— 「一直响」听起来就是个骚扰功能，而它的实际行为是「到教室或者
/// 上课就停」，这两句话在用户心里是完全不同的两件事。
class _RepeatTile extends StatelessWidget {
  const _RepeatTile({required this.scope});

  final ReminderScope scope;

  /// 档位。1 分钟是「人已经在路上了，催我一下」，15 分钟是「还有一节课的时间」。
  static const List<int> _presets = [1, 2, 3, 5, 10, 15];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = scope.values.repeatReminders;

    return Column(
      children: [
        SwitchListTile(
          title: const Text('反复提醒到教室'),
          subtitle: const Text(
            '每条提醒都带上「我已到教室」按钮；没按就每隔一段时间再弹一次',
          ),
          value: on,
          onChanged: (v) => scope.write((s) => s.copyWith(repeatReminders: v)),
        ),
        if (on) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '多久再弹一次',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          _IntervalPicker(scope: scope),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '按下「我已到教室」或者到了上课时间，这条提醒就停了 —— 不会一直响下去。'
              // 上课那条尤其要说：重复提醒的最后一跳正好落在上课那一刻，
              // 它做的事是把通知撤掉，而不是再弹一条「上课了」。
              '上课那一刻它会自己把还挂在通知栏里的那条撤掉。',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
        ],
      ],
    );
  }
}

class _IntervalPicker extends StatelessWidget {
  const _IntervalPicker({required this.scope});

  final ReminderScope scope;

  static String label(int minutes) =>
      minutes % 60 == 0 ? '${minutes ~/ 60} 小时' : '$minutes 分钟';

  @override
  Widget build(BuildContext context) {
    final current = scope.values.repeatIntervalMinutes;
    final isPreset = _RepeatTile._presets.contains(current);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in _RepeatTile._presets)
            ChoiceChip(
              label: Text(label(m)),
              selected: current == m,
              onSelected: (_) => scope.write(
                (s) => s.copyWith(repeatIntervalMinutes: m),
              ),
            ),
          ChoiceChip(
            label: Text(isPreset ? '自定义…' : label(current)),
            selected: !isPreset,
            onSelected: (_) => _pickCustom(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final controller = TextEditingController(
      text: scope.values.repeatIntervalMinutes.toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义重复间隔'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '每隔多久再弹一次',
            suffixText: '分钟',
            helperText: '1 到 120 分钟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (value == null) return;
    scope.write(
      (s) => s.copyWith(
        repeatIntervalMinutes: value.clamp(
          AppSettings.kMinRepeatMinutes,
          AppSettings.kMaxRepeatMinutes,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 地点
// ---------------------------------------------------------------------------

class _PlacesList extends ConsumerWidget {
  const _PlacesList({required this.settings, required this.notifier});

  final AppSettings settings;
  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (settings.places.isEmpty)
          const ListTile(
            title: Text('还没有记下的地点'),
            subtitle: Text(
              '在教室里点「添加地点」，用当前位置记一次就够；'
              '按楼记，不用一间间教室记。',
            ),
          ),
        for (final p in settings.places)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(p.name),
            subtitle: Text(
              '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: () => notifier.update(
                (s) => s.copyWith(
                  places: s.places.where((x) => x.name != p.name).toList(),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('添加地点'),
              onPressed: () => _addPlace(context, ref),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addPlace(BuildContext context, WidgetRef ref) async {
    final place = await showDialog<SavedPlace>(
      context: context,
      builder: (_) => const _PlaceDialog(),
    );
    if (place == null) return;
    // 同名覆盖而不是并存：匹配时「名字长的赢」，两条同名只会让结果取决于
    // 列表顺序，那是最难解释的一种不确定性。
    notifier.update(
      (s) => s.copyWith(
        places: [...s.places.where((x) => x.name != place.name), place],
      ),
    );
  }
}

class _PlaceDialog extends ConsumerStatefulWidget {
  const _PlaceDialog();

  @override
  ConsumerState<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends ConsumerState<_PlaceDialog> {
  final _name = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  bool _locating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    final loc = await ref.read(reminderSchedulerProvider).currentLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (loc == null) {
        // 失败的原因有好几种（没权限、定位关着、室内收不到星），
        // 这里不猜是哪一种，只说结果并把手工填的路留着。
        _error =
            '没能取到位置。检查一下定位权限和系统的定位开关，'
            '或者直接手工填经纬度。';
      } else {
        _lat.text = loc.lat.toStringAsFixed(6);
        _lng.text = loc.lng.toStringAsFixed(6);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('记一个地点'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '地点名',
                hintText: '第一教学楼',
                helperText: '课程地点里包含这个名字就算命中，按楼记即可',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '纬度',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '经度',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: _locating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(_locating ? '正在定位…' : '用当前位置'),
              onPressed: _locating ? null : _useCurrentLocation,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final place = SavedPlace.fromJson({
              'name': _name.text,
              'lat': _lat.text,
              'lng': _lng.text,
            });
            // 解析交给 SavedPlace.fromJson 而不是在这儿再写一遍校验：
            // 越界的坐标必须在**入口**就被挡住，落进设置文件之后再发现，
            // 表现是「门控永远判定不在教室」，跟没定位一模一样。
            if (place == null) {
              setState(() => _error = '地点名不能为空，经纬度要填数字且在合法范围内。');
              return;
            }
            Navigator.of(context).pop(place);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 权限状态
// ---------------------------------------------------------------------------

class _PermissionCards extends ConsumerWidget {
  const _PermissionCards({required this.caps});

  final AsyncValue<ReminderCapabilities> caps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = caps.value;
    if (c == null) {
      return const ListTile(title: Text('正在读取系统权限…'));
    }
    if (!c.supported) {
      return const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('这个平台还不支持课前提醒'),
        subtitle: Text('目前只有 Android 端实现了提醒。'),
      );
    }

    final scheduler = ref.read(reminderSchedulerProvider);
    final scheme = Theme.of(context).colorScheme;
    Future<void> refresh() async =>
        ref.invalidate(reminderCapabilitiesProvider);

    return Column(
      children: [
        ListTile(
          leading: Icon(
            c.notificationsGranted
                ? Icons.notifications_active
                : Icons.notifications_off,
          ),
          title: const Text('通知'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.notificationsGranted ? '已允许' : '被关掉了，提醒弹不出来'),
              // 「允许通知」和「看得见」是两件事，而**做完了前一件的人不会再去
              // 想后一件事**。真机上撞到过：通知一条不落地发出来了，屏幕上却什么
              // 都没有，只在通知栏里多一行。
              //
              // 但**只有渠道重要程度真的低于 HIGH 时才敢这么说**。原来的判据是
              // 应用级的重要程度，它对一个正常应用永远是 DEFAULT —— 于是这句断言
              // 永远挂着，用户照它去系统设置里找一个本来就是开的开关。
              if (c.notificationsGranted && !c.banners)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '但横幅被关掉了：现在只在通知栏里多一行，屏幕上不会弹出来。'
                    '上课前那条提醒的价值就是不用掏手机就能看见。',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                )
              // 渠道是 HIGH 只说明「按 Android 的规则该弹」：有的 ROM 在渠道
              // 之外还有一个 App 读不到的「悬浮通知」开关（见 Kotlin 侧注释）。
              // 所以这里既不报红也不下断言，只留一个入口 —— 真不弹的时候，
              // 用户在这页能自己找到地方改，而不是以为提醒坏了。
              else if (c.notificationsGranted)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '横幅最终由系统决定。要是提醒只出现在通知栏、屏幕上不弹，'
                    '就点右边打开「悬浮通知」。',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ),
            ],
          ),
          trailing: !c.notificationsGranted
              ? TextButton(
                  onPressed: () async {
                    await scheduler.requestNotification();
                    await refresh();
                  },
                  child: const Text('去允许'),
                )
              : TextButton(
                  onPressed: () async {
                    await scheduler.openNotificationSettings();
                    await refresh();
                  },
                  child: Text(c.banners ? '通知设置' : '去开启横幅'),
                ),
        ),
        if (c.notificationsGranted && !c.banners)
          const Padding(
            padding: EdgeInsets.fromLTRB(56, 0, 16, 8),
            child: Text(
              // 各家 ROM 对那个开关的叫法不一样，把可能的名字都列出来 ——
              // 只给个按钮的话用户会在通知设置页里找不到「横幅」两个字。
              '系统设置 → 通知 → 本应用里，把「横幅通知」（有的 ROM 叫「悬浮通知」'
              '或「弹出通知」）打开。这个开关只有系统设置里能改，App 改不了。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ListTile(
          leading: Icon(c.exactAlarms ? Icons.alarm_on : Icons.alarm),
          title: const Text('精确闹钟'),
          subtitle: Text(c.exactAlarms ? '可以准点响' : '只能大致到点，系统可能推迟几分钟'),
          trailing: c.exactAlarms
              ? null
              : TextButton(
                  onPressed: () async {
                    await scheduler.openExactAlarmSettings();
                    await refresh();
                  },
                  child: const Text('去设置'),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.my_location),
          title: const Text('位置'),
          subtitle: Text(switch (c.location) {
            LocationPermission.always => '始终允许 —— 定位门控可用',
            LocationPermission.foregroundOnly => '仅「使用应用时」—— 门控取不到位置',
            LocationPermission.denied => '未授予',
            LocationPermission.unsupported => '这个设备没有定位能力',
          }),
          trailing: c.location == LocationPermission.denied
              ? TextButton(
                  onPressed: () async {
                    await scheduler.requestLocation();
                    await refresh();
                  },
                  child: const Text('去授予'),
                )
              : c.location == LocationPermission.foregroundOnly
              ? TextButton(
                  onPressed: () async {
                    await scheduler.openLocationSettings();
                    await refresh();
                  },
                  child: const Text('改成始终允许'),
                )
              : null,
        ),
        if (c.location == LocationPermission.foregroundOnly)
          const Padding(
            padding: EdgeInsets.fromLTRB(56, 0, 16, 8),
            child: Text(
              '路径：应用信息 → 权限 → 位置信息 → 始终允许。'
              'Android 11 起系统不再弹这个选项，只能自己去开。',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 状态与自检
// ---------------------------------------------------------------------------

class _ReminderStatusCard extends ConsumerWidget {
  const _ReminderStatusCard({required this.caps});

  final AsyncValue<ReminderCapabilities> caps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 两个输入都 watch（而不是调个「算一遍」的方法）：这一行字要跟着课表和设置
    // 实时变，而 watch 就是「变了就重建」这件事的全部写法。一个月几十条提醒的
    // 计算量可以忽略，不值得为它做缓存。
    final settings = ref.watch(settingsProvider);
    final sessions = ref.watch(allSessionsProvider);
    final plan = buildReminderPlan(
      sessions: sessions,
      settings: settings,
      now: DateTime.now(),
    );

    final count = caps.value?.scheduledCount;
    final scheme = Theme.of(context).colorScheme;

    final first = plan.firstAt;
    final preview = first == null
        ? '未来一个月里没有要提醒的课。'
        : '最近一条：${first.month} 月 ${first.day} 日 '
              '${formatMinutes(first.hour * 60 + first.minute)}';

    return ListTile(
      leading: const Icon(Icons.event_available_outlined),
      title: Text('未来一个月排了 ${plan.specs.length} 条提醒'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(preview),
          if (plan.gatedCount > 0) Text('其中 ${plan.gatedCount} 条会在响之前先看一眼位置'),
          if (count != null && count != plan.specs.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '系统里现在排着 $count 条，和这个数字对不上 —— '
                '可能是刚才的改动还没同步完。',
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
          if (plan.truncated)
            Text(
              '超出上限的部分没有排 —— 会用到的提醒太多，'
              '最近 ${plan.specs.length} 条之外的没排上。',
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
        ],
      ),
    );
  }
}

class _TestReminderTile extends ConsumerStatefulWidget {
  const _TestReminderTile({required this.caps});

  final AsyncValue<ReminderCapabilities> caps;

  @override
  ConsumerState<_TestReminderTile> createState() => _TestReminderTileState();
}

class _TestReminderTileState extends ConsumerState<_TestReminderTile> {
  @override
  Widget build(BuildContext context) {
    final supported = widget.caps.value?.supported ?? false;
    return ListTile(
      leading: const Icon(Icons.notifications_none),
      title: const Text('试一条提醒'),
      subtitle: const Text('10 秒后弹一条，用来确认通知真的能弹出来'),
      enabled: supported,
      onTap: supported ? _fire : null,
    );
  }

  Future<void> _fire() async {
    // 先手动同步一次再试：用户可能刚改完设置，而同步还在 800ms 的合并窗口里；
    // 这时立刻测会用到旧表，看起来像「设置没生效」。
    await ref.read(nativeSyncProvider).flushNow();
    await ref
        .read(reminderSchedulerProvider)
        .testNotify(after: const Duration(seconds: 10));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('10 秒后弹一条通知，可以先退回桌面等着')));
  }
}
