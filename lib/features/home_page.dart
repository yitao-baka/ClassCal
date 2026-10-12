import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/settings_providers.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/schedule_ref.dart';
import '../core/theme/course_colors.dart';
import '../data/db/database.dart';
import '../data/exchange/classcal_json.dart';
import '../data/import/ics_import.dart';
import '../data/model/resolve.dart';
import 'editor/course_editor.dart';
import 'editor/session_sheet.dart';
import 'editor/shift_sheet.dart';
import 'export/export_actions.dart';
import 'import/import_wizard.dart';
import 'settings/reminder_page.dart';
import 'settings/settings_page.dart';
import 'timetable/week_grid.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(tabRowsProvider);
    final entries = ref.watch(tabEntriesProvider);
    final tab = ref.watch(effectiveTabProvider);
    final setId = ref.watch(effectiveSetIdProvider);

    // 「当前这一页是不是总览」和「用哪个 setId 当周次锚点」从这一轮起是**两个**
    // 问题：停在总览上时 setId 会回退到第一个日程（周次、小组件快照都要它），
    // 但那一页自身没有日程可操作 —— 改名、平移、导出 ICS、点空格子新增
    // 在总览里都无处落脚。
    final isOverview = tab?.isOverview ?? false;
    // 有没有任何一个日程。注意这一条**不看**当前页 —— 总览页里「导出 JSON 备份」
    // 仍然是有效的（它备份的是全部日程，和当前在看哪一页无关）。
    final hasSets = tabs.value?.isNotEmpty ?? false;
    final canActOnSet = !isOverview && setId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ClassCal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导入 ICS / JSON',
            onPressed: () => _pickAndImport(context, ref),
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: '更多',
            onSelected: (a) => _onMenu(context, ref, setId, a),
            itemBuilder: (context) {
              // 没有日程、或者正停在总览上时这几项无从谈起。置灰而不是藏起来 ——
              // 菜单项忽隐忽现比灰着更让人困惑，而且灰着的项还能起到
              // 「导入之后可以干这些」「切到某个日程就能干这个」的提示作用。
              return [
                _item(_MenuAction.shift, Icons.swap_vert, '整体平移',
                    isOverview ? '切到某个日程才能平移' : '前后挪动整学期',
                    canActOnSet),
                const PopupMenuDivider(),
                _item(_MenuAction.exportIcs, Icons.event_note_outlined, '导出 ICS',
                    '给别的日历软件用', canActOnSet),
                _item(_MenuAction.exportJson, Icons.backup_outlined,
                    '导出 JSON 备份', '完整备份，含改期记录', hasSets),
                const PopupMenuDivider(),
                _item(_MenuAction.rename, Icons.drive_file_rename_outline, '重命名日程',
                    null, canActOnSet),
                _item(_MenuAction.delete, Icons.delete_outline, '删除这个日程',
                    '不影响其它日程', canActOnSet, destructive: true),
                const PopupMenuDivider(),
                // 「本日程的提醒」放在这里，是因为**每个日程独立管理**这个功能
                // 原来的入口有四层深（设置 → 课前提醒 → 按日程分别设置 → 点某个日程），
                // 而用户心里想的是一句「这个日程的提醒」—— 他正看着那个日程，
                // 就该能从这里进去。
                //
                // 当前日程页里，提醒是**唯一**一项不适合塞进「整体平移」那种弹窗的
                // 东西：它有四节、有自己的子页面，而且总览没有提醒可配（同一批事件的
                // 另一个视图，给它一套提醒会让同一节课被两个日程各提醒一次）。
                _item(_MenuAction.reminder, Icons.alarm_outlined, '本日程的提醒',
                    isOverview ? '切到某个日程才能改' : '提前多久、门控、重复提醒',
                    canActOnSet),
                // 设置永远可点 —— 主题、配色跟有没有日程无关
                _item(_MenuAction.settings, Icons.settings_outlined, '设置',
                    '主题与配色', true),
              ];
            },
          ),
        ],
        // AppBar.bottom 要求 PreferredSizeWidget；_SetTabs 高度固定，
        // 用 PreferredSize 把它的高度报给 AppBar 即可。
        //
        // 少于两个条目就不显示整条标签栏，只有一个日程时总览也不参与
        // （见 tabEntriesProvider）—— 于是单日程用户看不到这条栏，右侧
        // 也没有一个和自己一模一样的「总览」。
        bottom: entries.length < 2
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: _SetTabs(entries: entries, selectedKey: tab?.key),
              ),
      ),
      body: tabs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: '$e'),
        data: (rows) {
          if (rows.isEmpty) {
            return _EmptyView(onImport: () => _pickAndImport(context, ref));
          }
          if (setId == null) return const Center(child: CircularProgressIndicator());
          if (isOverview) return _OverviewView(anchorId: setId);
          return _TimetableView(setId: setId);
        },
      ),
      // 总览里没有「新增」—— 加到哪个日程在那一页没有答案。
      // 点空格子那条路同样关掉（见 _OverviewView）。
      floatingActionButton: !canActOnSet
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddSheet(context, ref, setId),
              icon: const Icon(Icons.add),
              label: const Text('新增'),
            ),
    );
  }
}

/// 「新增」底下的三条路。
///
/// 这个位置原来是「导入」。但导入一学期只做一次，新增却是常做的事，而
/// 常做的事该占最好按的那颗按钮。导入没有被拿掉，只是退到这一层里 ——
/// 顶栏那个图标也还在。
///
/// 点空格子那条路（[WeekGrid.onTapEmptySlot]）仍然直奔「新增课程」，没有
/// 收拢到这里：那个场景下用户已经指了格子，再问一遍是白问。
Future<void> _showAddSheet(
  BuildContext context,
  WidgetRef ref,
  int setId,
) async {
  final data = ref.read(setDataProvider(setId)).value;
  if (data == null) return;

  final action = await showModalBottomSheet<_AddAction>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('新增单次事件'),
            subtitle: const Text('只有这一次，其它周不动'),
            onTap: () => Navigator.pop(sheet, _AddAction.oneOff),
          ),
          ListTile(
            leading: const Icon(Icons.library_add_outlined),
            title: const Text('新增课程'),
            subtitle: const Text('整学期每周重复'),
            onTap: () => Navigator.pop(sheet, _AddAction.course),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导入课表'),
            subtitle: const Text('ICS / JSON 文件'),
            onTap: () => Navigator.pop(sheet, _AddAction.import),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _AddAction.oneOff:
      await addOneOff(context, ref, setId, data,
          date: _defaultOneOffDate(ref, data));
    case _AddAction.course:
      await addCourse(context, ref, setId, data);
    case _AddAction.import:
      await _pickAndImport(context, ref);
  }
}

/// 新增单次事件时预填哪天。
///
/// 正在看的那一周里有今天就用今天；没有就落到那一周的周一。用户多半是在
/// 某一周里看见空位才想起来要补一件事的，默认写到「今天」会很意外 ——
/// 真要今天的话，今天那格本来就在眼前。
DateTime _defaultOneOffDate(WidgetRef ref, CalendarSetData data) {
  final week = ref.read(displayedWeekProvider);
  final monday = data.shifts.week1Monday.add(Duration(days: (week - 1) * 7));
  final today = DateTime.now();
  for (var i = 0; i < 7; i++) {
    final day = monday.add(Duration(days: i));
    if (day.year == today.year &&
        day.month == today.month &&
        day.day == today.day) {
      return today;
    }
  }
  return monday;
}

enum _AddAction { oneOff, course, import }

// ---------------------------------------------------------------------------
// 课表主体
// ---------------------------------------------------------------------------

class _TimetableView extends ConsumerWidget {
  const _TimetableView({required this.setId});

  final int setId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(setDataProvider(setId)).value;
    final sessions = ref.watch(resolvedSessionsProvider(setId));
    final week = ref.watch(displayedWeekProvider);
    final range = ref.watch(weekRangeProvider(setId));
    final now = ref.watch(nowProvider).value;

    if (data == null) return const Center(child: CircularProgressIndicator());

    final weekSessions = sessionsInWeek(sessions, week);

    return Column(
      children: [
        _WeekBar(
          week: week,
          range: range,
          hasSessions: weekSessions.isNotEmpty,
          onPrev: () => ref.read(viewedWeekProvider.notifier).show(week - 1),
          onNext: () => ref.read(viewedWeekProvider.notifier).show(week + 1),
          onToday: () => ref.read(viewedWeekProvider.notifier).reset(),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: WeekGrid(
              sessions: weekSessions,
              week: week,
              week1Monday: data.shifts.week1Monday,
              now: now,
              onTapSession: (s) => showSessionSheet(context, ref, setId, s),
              // 点空格子就在那一格新增一门课 —— 比「先点新增再挑星期和节次」
              // 少两步，而且不会选错格子。
              onTapEmptySlot: (weekday, startPeriod) =>
                  addCourse(context, ref, setId, data,
                      weekday: weekday, startPeriod: startPeriod),
            ),
          ),
        ),
        if (data.shifts.weekShift != 0 || data.shifts.timeShiftMinutes != 0)
          _ShiftBanner(
            weeks: data.shifts.weekShift,
            minutes: data.shifts.timeShiftMinutes,
            onTap: () => showShiftSheet(context, ref, setId),
            onReset: () => ref.read(repositoryProvider).resetShift(setId),
          ),
      ],
    );
  }

}

/// 总览页：**所有日程的事件合在一张周网格上**。
///
/// 三条和 [_TimetableView] 不同的地方，每一条都有明确理由：
///
/// * **按日期区间筛，不按 `week` 字段筛。** 周号是每个日程各自按自己的
///   `week1Monday` / `weekShift` 算的，「第 5 周」在两个日程里可能不是同一个
///   星期；比 `week` 会让其中一个日程整周错位。日期区间取自 [anchorId] 这个
///   日程的第 N 周 —— 总览自己没有周号，必须借一个坐标系。见
///   [sessionsInWeekRange]。
/// * **点空格子不新增**（`onTapEmptySlot: null`）：加到哪个日程在总览里没有答案。
/// * **点一条事件按它自己的 `setId` 打开**，而不是按当前标签页 ——
///   这是 `ResolvedSession.setId` 的第一个真实用途。
class _OverviewView extends ConsumerWidget {
  const _OverviewView({required this.anchorId});

  /// 借哪个日程的周次坐标系。**不是**「当前页是谁」—— 总览页没有自己的周号。
  final int anchorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(setDataProvider(anchorId)).value;
    final sessions = ref.watch(allSessionsProvider);
    final week = ref.watch(displayedWeekProvider);
    final range = ref.watch(weekRangeProvider(anchorId));
    final now = ref.watch(nowProvider).value;

    if (data == null) return const Center(child: CircularProgressIndicator());

    final weekSessions = sessionsInWeekRange(
      sessions,
      week1Monday: data.shifts.week1Monday,
      week: week,
    );

    return Column(
      children: [
        _WeekBar(
          week: week,
          range: range,
          hasSessions: weekSessions.isNotEmpty,
          onPrev: () => ref.read(viewedWeekProvider.notifier).show(week - 1),
          onNext: () => ref.read(viewedWeekProvider.notifier).show(week + 1),
          onToday: () => ref.read(viewedWeekProvider.notifier).reset(),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: WeekGrid(
              sessions: weekSessions,
              week: week,
              week1Monday: data.shifts.week1Monday,
              now: now,
              onTapSession: (s) => showSessionSheet(context, ref, s.setId, s),
              // 不加这一行就是「总览里点到空白处什么也不发生」，
              // 而那是刻意的：见类注释。
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.week,
    required this.range,
    required this.hasSessions,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final int week;
  final ({int first, int last}) range;
  final bool hasSessions;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child: Text(
                hasSessions ? '第 $week 周' : '第 $week 周 · 无课',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: hasSessions ? scheme.onSurface : scheme.outline,
                ),
              ),
            ),
          ),
          Text(
            '共 ${range.first}-${range.last} 周',
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.today),
            tooltip: '回到本周',
            onPressed: onToday,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _ShiftBanner extends StatelessWidget {
  const _ShiftBanner({
    required this.weeks,
    required this.minutes,
    required this.onTap,
    required this.onReset,
  });

  final int weeks;
  final int minutes;
  final VoidCallback onTap;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (weeks != 0) '${weeks > 0 ? '后移' : '前移'} ${weeks.abs()} 周',
      if (minutes != 0) '${minutes > 0 ? '后移' : '前移'} ${minutes.abs()} 分钟',
    ];
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Icon(Icons.swap_vert, size: 16, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // 横幅本身就是「调整平移」的入口，不必再回菜单里找
                  '已整体${parts.join('、')} · 点此调整',
                  style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
                ),
              ),
              TextButton(onPressed: onReset, child: const Text('撤销')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日程切换标签。
///
/// 刻意不用 `TabBar`：它需要 `TabController` + `TickerProvider`，而这里只是
/// 一组「选一个」的按钮，没有要联动的 `TabBarView`。硬套会为了动画引入一整套
/// 状态管理，还得在无状态组件里造 ticker。`ChoiceChip` 就是这件事的正确控件。
///
/// 渲染的是 [TabEntry] 而不是 `CalendarSet` —— 标签栏里现在有一个**不是日程**
/// 的条目（总览），拿 `List<CalendarSet>` 的话每一处消费标签的地方都得自己
/// 特判一次总览。
class _SetTabs extends ConsumerWidget {
  const _SetTabs({required this.entries, required this.selectedKey});

  /// 已经按用户设定的顺序排好（见 `tabEntriesProvider`）。
  final List<TabEntry> entries;

  /// 当前生效的那个条目的 key。传的是**生效**值而不是「用户手选的」值 ——
  /// 后者为 null（用户还没点过）时一个都不会高亮。
  final String? selectedKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final entry = entries[i];
          final selected = entry.key == selectedKey;
          final hex = entry.colorSeedHex;
          return ChoiceChip(
            selected: selected,
            onSelected: (_) =>
                ref.read(selectedTabProvider.notifier).select(entry.key),
            avatar: CircleAvatar(
              radius: 6,
              // 总览用中性色 —— 它不是某个日程，不该借用某个日程的颜色；
              // 借了就等于给「合并视图」编了一个它没有的身份。
              backgroundColor: entry.isOverview
                  ? scheme.outline
                  : parseHexColor(hex) ??
                      kCoursePalette[i % kCoursePalette.length],
            ),
            label: Text(entry.name),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 空态与错误
// ---------------------------------------------------------------------------

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 64, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text('还没有日程', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '导入教务系统导出的 .ics，或本 App 备份的 .json',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导入课表'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('出错了：$message', textAlign: TextAlign.center),
        ),
      );
}

// ---------------------------------------------------------------------------
// 导入
// ---------------------------------------------------------------------------

enum _MenuAction { shift, exportIcs, exportJson, reminder, rename, delete, settings }

PopupMenuItem<_MenuAction> _item(
  _MenuAction action,
  IconData icon,
  String title,
  String? subtitle,
  bool enabled, {
  bool destructive = false,
}) =>
    PopupMenuItem(
      value: action,
      enabled: enabled,
      child: Consumer(
        // 菜单项要按主题上色，得拿得到 context 的 Theme —— 用一个
        // 轻量 Consumer 包一层，避免整个菜单随主题重建。
        builder: (context, ref, _) => ListTile(
          dense: true,
          leading: Icon(
            icon,
            size: 20,
            color: enabled && destructive
                ? Theme.of(context).colorScheme.error
                : null,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: enabled && destructive
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          subtitle: subtitle == null ? null : Text(subtitle),
        ),
      ),
    );

Future<void> _onMenu(
  BuildContext context,
  WidgetRef ref,
  int? setId,
  _MenuAction action,
) async {
  // 设置跟课表无关，得排在上面那个守卫**之前**处理，否则一套课表都没有时
  // 菜单里能看见「设置」却点不动。
  if (action == _MenuAction.settings) {
    showSettingsPage(context);
    return;
  }

  // 「本日程的提醒」也在守卫**之前**：它只要一个 setId，不需要那份
  // `setDataProvider`。放到守卫后面的话，课表刚导入、`setDataProvider` 还没
  // 吐出数据的那一帧点它会**静默什么都不发生** —— 而菜单项那时是亮的
  // （`canActOnSet` 只看 setId），看起来就是「点了没反应」。
  if (action == _MenuAction.reminder) {
    if (setId != null) showSetReminderPage(context, setId);
    return;
  }

  final data = setId == null ? null : ref.read(setDataProvider(setId)).value;
  if (setId == null || data == null) return;

  switch (action) {
    case _MenuAction.settings:
    case _MenuAction.reminder:
      // 上面已经提前返回了，这里只是让 switch 穷尽。
      break;
    case _MenuAction.shift:
      await showShiftSheet(context, ref, setId);
    case _MenuAction.exportIcs:
      await exportIcsSet(context, ref, setId);
    case _MenuAction.exportJson:
      await exportJsonBackup(context, ref);
    case _MenuAction.rename:
      await _rename(context, ref, setId, data.name);
    case _MenuAction.delete:
      await _deleteSet(context, ref, setId, data.name);
  }
}

Future<void> _rename(
  BuildContext context,
  WidgetRef ref,
  int setId,
  String current,
) async {
  final controller = TextEditingController(text: current);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('重命名日程'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty) return;
  await ref.read(repositoryProvider).renameSet(setId, name);
}

Future<void> _deleteSet(
  BuildContext context,
  WidgetRef ref,
  int setId,
  String name,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('删除「$name」？'),
      content: const Text('这个日程连同它的全部课程、单次事件和改期记录都会被移除，且无法撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(repositoryProvider).deleteSet(setId);

  // 顺手清掉这个日程的提醒覆盖。
  //
  // 不清也无害 —— id 是 `INTEGER PRIMARY KEY AUTOINCREMENT`，永不复用，那条
  // 孤儿记录再也认不到主人，查不到就当作没设过。但留着会让 `settings.json` 里积
  // 一堆对不上日程的块，以后排查「这个日程怎么不提醒」时会白白多花时间。
  //
  // **只在这一处清，不要在 `NativeSync` 里顺手清**：那边有一道「日程列表还在
  // 加载就先别动」的守卫，在「还没读出来」的那一帧动手会把用户**所有**日程的
  // 设置删光。这里手里有确切的 setId，是唯一安全的时机。
  ref.read(settingsProvider.notifier).update((s) {
    if (!s.setReminders.containsKey(setId)) return s;
    final next = Map<int, SetReminderSettings>.from(s.setReminders)..remove(setId);
    return s.copyWith(setReminders: next);
  });
  // 删掉的正好是当前手选的那一项才清掉选择，退回去「跟随默认页」。
  //
  // **必须判一下是哪一个**：手选的是 A、删掉的是 B 时也清掉的话，用户会被
  // 无端从 A 弹走。而且这一句本身已经不再是「否则会一直停在加载中」那种救命的
  // 处理了 —— `effectiveTabProvider` 的三级回退里，指向已删日程的那一级
  // 本来就查不到，会自然落到下一级。这里清掉只是别在内存里留一个死 key。
  final selected = ref.read(selectedTabProvider);
  if (selected == ScheduleRef.ofSet(setId)) {
    ref.read(selectedTabProvider.notifier).select(null);
  }
}

Future<void> _pickAndImport(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFiles();
  if (picked.isEmpty) return;
  final file = picked.first;
  final bytes = await file.readAsBytes();

  // ICS 规范要求 UTF-8；少数导出工具会带 BOM，去掉再解析。
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);

  final isJson = file.extension?.toLowerCase() == 'json';
  if (!context.mounted) return;

  try {
    final outcome = isJson
        ? await _importJson(ref, text, file.name)
        : await _importIcs(context, ref, text, file.name);
    if (outcome == null) return;
    ref.read(selectedTabProvider.notifier).select(ScheduleRef.ofSet(outcome.setId));
    ref.read(viewedWeekProvider.notifier).reset();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(outcome.message)),
    );
  } catch (e) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入失败'),
        content: Text('$e'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// 导入的结果：落到哪一套、以及给用户看的一句话。
class _ImportOutcome {
  const _ImportOutcome(this.setId, this.message);
  final int setId;
  final String message;
}

/// 走一遍导入向导。返回 null 表示用户取消。
Future<_ImportOutcome?> _importIcs(
  BuildContext context,
  WidgetRef ref,
  String text,
  String fileName,
) async {
  final initial = importIcs(text, sourceName: fileName);
  if (initial.set.templates.isEmpty) {
    throw const FormatException('文件里没有解析出任何课程');
  }
  if (!context.mounted) return null;

  final plan = await showImportWizard(
    context,
    initial: initial,
    sourceName: fileName,
    reparse: (anchor) => importIcs(text, sourceName: fileName, week1Monday: anchor),
  );
  if (plan == null) return null;
  final repo = ref.read(repositoryProvider);
  final tabs = ref.read(tabRowsProvider).value ?? const <CalendarSet>[];

  // 合并的目标可能有自己的锚点。此时必须**按目标那一套的锚点重新解析**：
  // 文件里的「第 5 周」在合并后应该落在目标的第 5 周，而不是文件自己
  // 推算出来的那个第 5 周 —— 后者的日期跟目标根本对不上号。
  final target = switch (plan.target) {
    MergeInto(setId: final id) => tabs.where((t) => t.id == id).firstOrNull,
    _ => null,
  };
  final anchor = target?.week1Monday ?? plan.anchor;
  final data = importIcs(
    text,
    sourceName: fileName,
    week1Monday: anchor,
    setName: target == null ? plan.name : null,
  ).set;

  switch (plan.target) {
    case null:
      return null;

    case MergeInto(setId: final id):
      final r = await repo.mergeIntoSet(id, data);
      return _ImportOutcome(
        id,
        '已并入「${target?.name ?? fileName}」：新增 ${r.added} 门，合并 ${r.merged} 门',
      );

    case NewTab():
      final id = await repo.createSet(data);
      return _ImportOutcome(id, '已导入「${plan.name}」');
  }
}

Future<_ImportOutcome?> _importJson(WidgetRef ref, String text, String fileName) async {
  final sets = decodeSets(text);
  if (sets.isEmpty) throw const FormatException('备份文件里没有任何日程');

  final repo = ref.read(repositoryProvider);
  var firstId = CalendarSetData.unsavedId;
  for (final s in sets) {
    final id = await repo.createSet(s);
    if (firstId == CalendarSetData.unsavedId) firstId = id;
  }
  return _ImportOutcome(firstId, '已从备份恢复 ${sets.length} 个日程');
}
