/// 桌面小组件的设置与配置。
///
/// 配置 UI **只写这一份**（Flutter 的，和 App 观感一致），没有原生配置页 ——
/// 这是刻意的取舍，理由写在 `WidgetRenderer` 的注释里：`MainActivity` 同时是
/// 「App 本身」和「配置页」时，`singleTop` + `taskAffinity=""` 会让「取消配置」
/// 把用户正在用的 App 一起关掉。代价是首次添加时看到的是默认样式。
///
/// 这一页最重要的一块是**实时预览**。它不是临时脚手架：`adb shell cmd appwidget`
/// 在这台 ROM 上不可用，没有任何命令行办法把小组件绑到桌面上，所以「布局对不对、
/// 配色对不对、数据对不对」全靠它 + 截图来验证 —— 而它同时就是用户要看的那个预览。
///
/// 每个实例有三个独立的选项：**画什么**（内容）、**画哪个日程**（`setKey`）、
/// **写不写日程名**。三项都落在这一页，包括用户说的「添加时允许设置显示哪个日程」
/// —— 按**能力**而不是**时机**满足：入口是这一页和桌面卡片上的齿轮。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/native_sync.dart';
import '../../app/providers.dart';
import '../../core/platform/home_widget.dart';
import '../../core/settings/schedule_ref.dart';
import '../../data/db/database.dart';

void showWidgetPage(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const WidgetPage()));

/// 从齿轮进来：直接落到某个实例的配置页。
void showWidgetConfigPage(BuildContext context, int instanceId) =>
    pushWidgetConfig(Navigator.of(context), instanceId);

/// 同上，但只给一个 [NavigatorState]。
///
/// 齿轮那条路是从 `main.dart` 里推的（`consumeLaunch()` 拿回一个 appWidgetId
/// 时），那里手上没有 `BuildContext`，只有 `navigatorKey.currentState`。
void pushWidgetConfig(NavigatorState navigator, int instanceId) =>
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => WidgetConfigPage(instanceId: instanceId),
      ),
    );

/// 桌面上现在放着哪些实例。
///
/// 每次进页面重新查一遍而不是缓存：用户随时可能拖上来一个或者删掉一个，
/// 而一份过期的列表会让「设置里显示着两个，桌面上只有一个」这种对不上的
/// 情况出现，用户只会以为列表是坏的。
final homeWidgetInstancesProvider = FutureProvider<List<HomeWidgetInstance>>(
  (ref) => ref.watch(homeWidgetBridgeProvider).instances(),
);

/// 原生侧的状态（放了几个、快照在不在）。
final homeWidgetStatusProvider = FutureProvider<HomeWidgetStatus>(
  (ref) => ref.watch(homeWidgetBridgeProvider).status(),
);

/// 一档尺寸 + 一种内容 + 一个日程 + 一个开关 = 一张预览图。
///
/// 四项全进 key，因为原生那边 `blockFor` 和行数预算（`LABEL_DP` 进 `chrome`）
/// 都是**看这两个新值**的：提前面不收进来，用户改完日程之后预览会停在旧那张图上
/// —— 而这一页的预览就是唯一能看渲染结果的地方。
@immutable
class _PreviewKey {
  const _PreviewKey(this.content, this.setKey, this.showSetName, this.widthDp, this.heightDp);

  final WidgetContent content;
  final String setKey;
  final bool showSetName;
  final int widthDp;
  final int heightDp;

  @override
  bool operator ==(Object other) =>
      other is _PreviewKey &&
      other.content == content &&
      other.setKey == setKey &&
      other.showSetName == showSetName &&
      other.widthDp == widthDp &&
      other.heightDp == heightDp;

  @override
  int get hashCode => Object.hash(content, setKey, showSetName, widthDp, heightDp);
}

/// 预览图。
///
/// 原生侧返回 null 表示「渲染不出来」—— 最常见的原因是还没有快照（App 装上
/// 之后从没同步过）。那时画一句提示，而不是让界面卡在转圈上。
final _previewProvider =
    FutureProvider.family<Uint8List?, _PreviewKey>((ref, key) {
  return ref.watch(homeWidgetBridgeProvider).preview(
        content: key.content,
        setKey: key.setKey,
        showSetName: key.showSetName,
        widthDp: key.widthDp,
        heightDp: key.heightDp,
      );
});

/// 这个实例存着的 key **实际会画成什么**。
///
/// 存的 key 可能指着一个**已经被删掉的日程**。原生那边 `blockFor` 的兜底是
/// 「退回 `activeSetId` 那一块」，也就是跟随当前 —— 所以这里把它显示成
/// 「跟随当前」不是掩饰，而是**如实描述它现在画的东西**。
/// （drift 的 id 带 AUTOINCREMENT，用过的不复用，所以不存在「那个 id 又回来了」。）
///
/// 不做这件事的后果：单选组里一项都不选中，用户看到的是「这个实例的配置丢了」。
String _effectiveSetKey(String stored, List<CalendarSet> rows) {
  if (stored == ScheduleRef.overview || stored == ScheduleRef.follow) return stored;
  final id = ScheduleRef.setIdOf(stored);
  if (id != null && rows.any((r) => r.id == id)) return stored;
  return ScheduleRef.follow;
}

/// [_effectiveSetKey] 的人话版本，给「桌面上已有的」那个列表用。
///
/// 摘要里带上这一项不是装饰：三个实例各配一种日程是本轮最主要的用法，
/// 而列表上只写「今天的课」的话，三个实例看起来会完全一样。
String _setLabel(String stored, List<CalendarSet> rows) {
  final key = _effectiveSetKey(stored, rows);
  if (key == ScheduleRef.follow) return '跟随当前';
  final id = ScheduleRef.setIdOf(key);
  for (final r in rows) {
    if (r.id == id) return r.name;
  }
  return '总览';
}

/// 三方都需要的档位表。和原生侧 `WidgetRenderer.effectiveContent` 的阶梯
/// 是同一个语义 —— 那边读快照里的阈值，这边只是给用户看个说明，
/// 真正决定画什么的是原生那一段。
///
/// 这几个数字是**启动器报回来的典型尺寸**，不是 `appwidget-provider` 里写的
/// `minWidth/minHeight`。两者差得很远：`minWidth/minHeight` 只用来算「占几格」
/// （所以 2×1 写的是 110×40），而真正排版时拿到的是「格数 × 格子尺寸」——
/// 一个 2×1 在 4 列网格上大约 **190×84dp**。拿 110×40 去预览，看到的是
/// 一个永远不会出现的尺寸，还会因为塞不下三行而误以为布局坏了。
const List<({String label, int widthDp, int heightDp})> _sizePresets = [
  (label: '小 2×1', widthDp: 190, heightDp: 84),
  (label: '中 4×2', widthDp: 380, heightDp: 170),
  (label: '大 4×4', widthDp: 380, heightDp: 380),
];

String _contentLabel(WidgetContent c) => switch (c) {
      WidgetContent.auto => '跟随尺寸',
      WidgetContent.next => '下一节课',
      WidgetContent.today => '今天的课',
      WidgetContent.todayTomorrow => '今天 + 明天',
      WidgetContent.week => '本周课表',
    };

String _contentSubtitle(WidgetContent c) => switch (c) {
      WidgetContent.auto => '小 → 下一节课，中 → 今天的课，大 → 本周课表',
      WidgetContent.next => '只显示最近的一节，字最大',
      WidgetContent.today => '今天一天的课，一行一节',
      WidgetContent.todayTomorrow => '两组，今天和明天各一组',
      WidgetContent.week => '一周的彩色小格子，看出来哪几天满',
    };

class WidgetPage extends ConsumerStatefulWidget {
  const WidgetPage({super.key});

  @override
  ConsumerState<WidgetPage> createState() => _WidgetPageState();
}

class _WidgetPageState extends ConsumerState<WidgetPage> {
  int _preset = 0;

  /// 预览要画哪种内容。
  ///
  /// 默认「跟随尺寸」，但**可以单独选** —— 四个布局里「今天 + 明天」在任何
  /// 尺寸下都不会被 `auto` 选中（小→下一节、中→今天、大→本周），
  /// 没有这个选择器它就永远验证不到。而这一页的预览是**唯一**能在没有桌面
  /// 小组件的情况下看渲染结果的手段（`adb shell cmd appwidget` 在 API 36 的
  /// 镜像上也没有实现），漏掉一个布局等于闭着眼睛发。
  WidgetContent _content = WidgetContent.auto;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 用户去桌面加一个、拖一下、或者在「小组件」里删掉，都会让这里缓存的那份
    // 列表过期。而「去桌面操作 → 回来」正是这一页最主流的用法，不重查的话
    // 每次回来看到的都是上次的答案，只能退出重进。
    _lifecycle = AppLifecycleListener(onResume: _reload);
  }

  void _reload() {
    ref.invalidate(homeWidgetInstancesProvider);
    ref.invalidate(homeWidgetStatusProvider);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(homeWidgetStatusProvider);
    final instances = ref.watch(homeWidgetInstancesProvider);
    final rows = ref.watch(tabRowsProvider).value ?? const <CalendarSet>[];

    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件')),
      body: ListView(
        children: [
          _statusTile(context, status),
          const Divider(),
          _section(context, '桌面上已有的'),
          instances.when(
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      '还没有放置任何小组件。长按桌面 → 小组件，找到「ClassCal」'
                      '拖到桌面上即可；加完之后回到这一页就能在这里配置它。',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                : Column(
                    children: [
                      for (final it in list)
                        ListTile(
                          leading: const Icon(Icons.widgets_outlined),
                          title: Text('${it.widthDp} × ${it.heightDp} dp'),
                          subtitle: Text(
                            '${_contentLabel(it.content)} · '
                            '${_setLabel(it.setKey, rows)}'
                            '${it.showSetName ? '' : ' · 不写日程名'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => showWidgetConfigPage(context, it.id),
                        ),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('读不到桌面上的小组件：$e', style: const TextStyle(fontSize: 12)),
            ),
          ),
          const Divider(),
          _section(context, '预览'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '下面是原生侧真实渲染出来的图 —— 和桌面上那张卡片走的是同一段'
              '代码、同一份数据。尺寸取的是启动器实际报回来的典型值，'
              '跟你手机上那张卡片可能差几个像素。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _sizePresets.length; i++)
                  ChoiceChip(
                    label: Text(_sizePresets[i].label),
                    selected: _preset == i,
                    onSelected: (_) => setState(() => _preset = i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in WidgetContent.values)
                  ChoiceChip(
                    label: Text(_contentLabel(c)),
                    selected: _content == c,
                    onSelected: (_) => setState(() => _content = c),
                  ),
              ],
            ),
          ),
          // 这一页的预览固定画「总览 + 带日程名」——那正是**刚拖到桌面上、还没
          // 配置过**的实例的样子（三处默认值：内容跟随尺寸、日程总览、日程名显示）。
          // 想预览别的组合就进某个实例的配置页，那里三项都能改、预览跟着变。
          _PreviewPane(
            content: _content,
            setKey: ScheduleRef.overview,
            showSetName: true,
            widthDp: _sizePresets[_preset].widthDp,
            heightDp: _sizePresets[_preset].heightDp,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              '「跟随尺寸」就是按这一档自动挑内容：小画下一节课、中画今天的课、'
              '大画本周课表。想让某个例子一直显示某一种，进它的配置页选定即可 ——'
              '就算把它缩小到放不下，也照你选的那样画。\n\n'
              '上面这张预览画的是总览、并且带着日程名 —— 也就是刚拖到桌面上、'
              '还没配置过的样子。每个实例显示哪个日程，在它自己的配置页里改。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTile(BuildContext context, AsyncValue<HomeWidgetStatus> status) {
    final scheme = Theme.of(context).colorScheme;
    return status.when(
      data: (s) {
        if (!s.supported) {
          return const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('当前平台不支持'),
            subtitle: Text('桌面小组件目前只有 Android 端有；Windows 端会在后面的阶段做。'),
          );
        }
        return ListTile(
          leading: Icon(
            s.hasSnapshot ? Icons.check_circle_outline : Icons.error_outline,
            color: s.hasSnapshot ? scheme.primary : scheme.error,
          ),
          title: Text(s.hasSnapshot ? '课表数据已同步' : '还没有同步过课表'),
          subtitle: Text(
            s.hasSnapshot
                ? '桌面上放着 ${s.count} 个；数据时间 ${_shortTime(s.snapshotAt)}'
                : '打开一次 App 就会把课表推给桌面。数据推下去之前，'
                    '小组件只会显示一句提示。',
          ),
        );
      },
      loading: () => const ListTile(
        leading: Icon(Icons.hourglass_empty),
        title: Text('正在读取状态…'),
      ),
      error: (e, _) => ListTile(
        leading: Icon(Icons.error_outline, color: scheme.error),
        title: const Text('读不到小组件状态'),
        subtitle: Text('$e'),
      ),
    );
  }
}

/// 单个实例的配置。
class WidgetConfigPage extends ConsumerStatefulWidget {
  const WidgetConfigPage({super.key, required this.instanceId});

  final int instanceId;

  @override
  ConsumerState<WidgetConfigPage> createState() => _WidgetConfigPageState();
}

class _WidgetConfigPageState extends ConsumerState<WidgetConfigPage> {
  // 三个待写的值。用「本地优先、否则读实例」而不是每次回读实例：
  // `setConfig` 是异步的，而下一帧 `homeWidgetInstancesProvider` 还没重建，
  // 直接读实例会让刚点的那个选项**弹回**去。
  WidgetContent? _pending;
  String? _pendingSetKey;
  bool? _pendingShowSetName;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 拖一下尺寸再回来，这一页要显示新的那个尺寸 —— 而尺寸是这一页最需要
    // 说准的数字：预览就是按它渲染的。
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(homeWidgetInstancesProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// 三个值**一次写完**，只传这次改动的那一项。
  ///
  /// 拆成三个方法会让每一次点击都产生一个「写了一半」的中间态：改日程的那一刻，
  /// 卡片会先用旧内容重画一次、再被下一次调用重画回去 —— 桌面上看起来就是闪了
  /// 一下。配置页手上本来就同时有这三个值，没有理由分三次发。
  ///
  /// 不「点保存才生效」：这一页的预览画的就是结果，再要求按一次保存只是多一步。
  void _write(
    HomeWidgetInstance it, {
    WidgetContent? content,
    String? setKey,
    bool? showSetName,
  }) {
    final c = content ?? _pending ?? it.content;
    final k = setKey ?? _pendingSetKey ?? it.setKey;
    final s = showSetName ?? _pendingShowSetName ?? it.showSetName;
    setState(() {
      _pending = c;
      _pendingSetKey = k;
      _pendingShowSetName = s;
    });
    ref
        .read(homeWidgetBridgeProvider)
        .setConfig(it.id, c, setKey: k, showSetName: s);
  }

  @override
  Widget build(BuildContext context) {
    final instances = ref.watch(homeWidgetInstancesProvider);
    // 日程列表从 `tabRowsProvider` 拿（数据库顺序），**不是** `tabEntriesProvider`
    // ——后者会在「只有一个日程」或「总览被关掉」时把总览从列表里摘掉，而那是
    // **标签栏**的规矩。小组件能不能显示总览和标签栏上有没有那一条是两件事：
    // 用户关掉总览标签页的意思不是「不许小组件合并显示」。
    final rows = ref.watch(tabRowsProvider).value ?? const <CalendarSet>[];

    return Scaffold(
      appBar: AppBar(title: const Text('小组件设置')),
      body: instances.when(
        data: (list) {
          final it = list.where((e) => e.id == widget.instanceId).firstOrNull;
          if (it == null) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '这个小组件已经不在桌面上了。桌面上现有的实例会出现在上一页。',
              ),
            );
          }
          final content = _pending ?? it.content;
          final setKey = _pendingSetKey ?? _effectiveSetKey(it.setKey, rows);
          final showSetName = _pendingShowSetName ?? it.showSetName;
          return ListView(
            children: [
              _section(context, '显示什么'),
              RadioGroup<WidgetContent>(
                groupValue: content,
                onChanged: (v) {
                  if (v == null) return;
                  _write(it, content: v);
                },
                child: Column(
                  children: [
                    for (final c in WidgetContent.values)
                      RadioListTile<WidgetContent>(
                        value: c,
                        title: Text(_contentLabel(c)),
                        subtitle: Text(_contentSubtitle(c)),
                      ),
                  ],
                ),
              ),
              const Divider(),
              _section(context, '显示哪个日程'),
              RadioGroup<String>(
                groupValue: setKey,
                onChanged: (v) {
                  if (v == null) return;
                  _write(it, setKey: v);
                },
                child: Column(
                  children: [
                    const RadioListTile<String>(
                      value: ScheduleRef.follow,
                      title: Text('跟随当前'),
                      subtitle: Text('在 App 里切到哪个日程，桌面上就跟着换'),
                    ),
                    const RadioListTile<String>(
                      value: ScheduleRef.overview,
                      title: Text('总览'),
                      subtitle: Text('所有日程合在一起显示（新加的小组件默认这个）'),
                    ),
                    // 日程名不写副标题：有十个日程就是十行一样的话。
                    for (final r in rows)
                      RadioListTile<String>(
                        value: ScheduleRef.ofSet(r.id),
                        title: Text(r.name),
                      ),
                  ],
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '还没有导入任何日程，所以只能显示总览。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              const Divider(),
              _section(context, '日程名'),
              SwitchListTile(
                value: showSetName,
                title: const Text('显示日程名'),
                // 这一句原来写的是「小尺寸（2×1）那一档本来就没有这一栏」。
                // **按尺寸说是不对的**，真机上一试就露：把 2×1 的内容固定成
                // 「本周课表」，那一栏照样出现（`weekView` 用的是带 `set_label`
                // 的那个布局）。有没有这一栏只取决于**挑中的是哪个布局** ——
                // 也就是「内容是不是『下一节课』」，跟尺寸无关：`nextView` 放不下
                // （色条 + eyebrow + 课名 + 教室已经排满），另外两种都放得下。
                // 而「跟随尺寸」在最小那一档挑的正是「下一节课」，所以那个常见的
                // 2×1 确实看不到它 —— 原话想说的就是这个，只是说成了尺寸。
                subtitle: const Text(
                  '在卡片上写一行这是哪个日程。关掉可以多显示一行课 —— '
                  '日程名约占半行高。内容选「下一节课」时没有这一栏（默认的 '
                  '2×1 就是它，四个控件已经排满），选另外两种才有；'
                  '开关照旧保存着，换回来时会自己回来。',
                ),
                onChanged: (v) => _write(it, showSetName: v),
              ),
              const Divider(),
              _section(context, '预览（${it.widthDp} × ${it.heightDp} dp）'),
              const Padding(
                // 原话是「这是这个实例当前在桌面上的尺寸」—— 把启动器**报回来**
                // 的那个数说成了卡片**真正占**的那个数，而两者差得不小：
                // 真机上 `OPTION_APPWIDGET_MAX_*` 报 128×70 的 2×1，实际排版拿到
                // 的是「格数 × 格子尺寸」（约 190×84）；实测一个报 200×242 的实例，
                // 桌面上的实际外框是 250×250。
                //
                // 于是这个预览**一定比桌面挤**，而挤最先露出来的就是那一格：
                // 标题折成两行、教室被挤出卡片 —— 看起来完全像渲染坏了。
                // `_sizePresets` 上面那段注释已经写过同一个坑（「还会因为塞不下
                // 三行而误以为布局坏了」），只是那条说的是通用档位；这里把话说在
                // 明处，别让同一件事从每个实例的配置页再骗一次人。
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '这是启动器报回来的尺寸，比卡片真正占的地方小 —— 真机上通常更宽裕，'
                  '这里看着挤不代表桌面上也挤。上面三项改完这里立刻跟着变；'
                  '想改尺寸就在桌面上拖着边缘缩放，回来就会跟着变。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              _PreviewPane(
                content: content,
                setKey: setKey,
                showSetName: showSetName,
                widthDp: it.widthDp,
                heightDp: it.heightDp,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
        loading: () => const Center(child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        )),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('读不到这个实例：$e'),
        ),
      ),
    );
  }
}

/// 预览图本身。
class _PreviewPane extends ConsumerWidget {
  const _PreviewPane({
    required this.content,
    required this.setKey,
    required this.showSetName,
    required this.widthDp,
    required this.heightDp,
  });

  final WidgetContent content;

  /// [ScheduleRef] 词表里的串。**必须和实例配置里存的那个值是同一个形状**，
  /// 否则预览画的是另一块、而用户按预览去桌面上找，找不到。
  final String setKey;
  final bool showSetName;
  final int widthDp;
  final int heightDp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = _PreviewKey(content, setKey, showSetName, widthDp, heightDp);
    final preview = ref.watch(_previewProvider(key));
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Center(
        child: preview.when(
          data: (bytes) => bytes == null
              ? Text(
                  '渲染不出来。多半是还没有课表数据 —— 打开一次 App 的课表页即可。',
                  style: TextStyle(fontSize: 12, color: scheme.error),
                )
              // 用真实比例显示：一张 190×84 的预览就该看起来又扁又小，
              // 把它拉成满宽会让用户以为小组件有那么宽。
              //
              // 只有在真实尺寸放不下时才等比缩一点 —— 4×4 的 380dp 比页面可用
              // 宽度还宽，直接摆会溢出；缩放比不缩放诚实，因为桌面上那张卡片
              // 也是被启动器缩着排的。
              : LayoutBuilder(
                  builder: (context, box) {
                    final scale = (box.maxWidth / widthDp).clamp(0.0, 1.0);
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.memory(
                        bytes,
                        width: widthDp * scale,
                        height: heightDp * scale,
                        fit: BoxFit.fill,
                        // 位图本身是原生的像素，按 dp 显示会随设备密度缩放 ——
                        // 和桌面上那张卡片一样。
                        filterQuality: FilterQuality.medium,
                      ),
                    );
                  },
                ),
          loading: () => const SizedBox(
            width: 40,
            height: 40,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('预览失败：$e', style: TextStyle(fontSize: 12, color: scheme.error)),
        ),
      ),
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

String _shortTime(int ms) {
  if (ms <= 0) return '未知';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
