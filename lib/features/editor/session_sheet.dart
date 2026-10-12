/// 点一节课弹出的详情面板 —— 也是所有「针对某一次课」的操作入口。
///
/// 这里要分清两类操作，它们的**作用范围完全不同**，混在一起用户一定会误伤：
///
/// * 单次调整（改期 / 停课一次 / 撤销调整）——只动这一次，写 `OccurrenceOverride`。
/// * 结构性修改（编辑这门课 / 删除这门课）——动的是整学期的那条规律。
///
/// 所以两组按钮在版面上明确分开，并且结构性那两个带二次确认。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/course_colors.dart';
import '../../core/time/periods.dart';
import '../../data/model/resolve.dart';
import 'course_editor.dart';

Future<void> showSessionSheet(
  BuildContext context,
  WidgetRef ref,
  int setId,
  ResolvedSession s,
) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SessionSheet(setId: setId, session: s),
    );

class _SessionSheet extends ConsumerWidget {
  const _SessionSheet({required this.setId, required this.session});

  final int setId;
  final ResolvedSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(setDataProvider(setId)).value;
    if (data == null) return const SizedBox.shrink();
    // 面板不拿外面传进来的那份快照渲染，而是每次按最新的数据重新解析一遍。
    //
    // 传进来的 `session` 是**点击那一刻**的解析结果。停课、改期之后它立刻过期，
    // 面板却还显示着旧状态 —— 刚点了「停课一次」，按钮还是「停课一次」，
    // 「撤销停课」还是灰的，得关掉重开才看得到自己刚才做了什么。
    final s = _fresh(data) ?? session;

    // 删除要按**课程名**分组，所以取的必须是规则本身的课程名，不能是 s.title ——
    // 后者可能是「单次改名」覆盖出来的临时名字。
    final courseTitle = _templateTitle(data, s);

    final scheme = Theme.of(context).colorScheme;
    final isOneOff = s.ruleId == null;
    final canUndo = s.adjusted && s.ruleId != null && s.originalDate != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: courseColor(s.title, overrideHex: s.colorHex),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.title, style: Theme.of(context).textTheme.titleLarge),
                ),
                if (s.cancelled)
                  Chip(
                    label: const Text('已停课', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.surfaceContainerHighest,
                    side: BorderSide(color: scheme.outlineVariant),
                  )
                else if (s.adjusted)
                  Chip(
                    label: const Text('已调整', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.tertiaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _detail(context, Icons.event, _dateLine(s)),
            _detail(context, Icons.schedule,
                '${formatMinutes(s.startMinute)} – ${formatMinutes(s.endMinute)}'),
            if (s.location.isNotEmpty) _detail(context, Icons.place, s.location),
            if (s.teacher.isNotEmpty) _detail(context, Icons.person, s.teacher),
            if (s.note.isNotEmpty) _detail(context, Icons.notes, s.note),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // 停课的那次只留一个出口。把「改期」「停课一次」也摆出来会让人以为
            // 还能在这一天上做文章，实际上这次课已经不上了。
            if (s.cancelled)
              _actionRow(
                context,
                [
                  _Action('撤销停课', Icons.event_available,
                      canUndo ? () => _undoAndClose(context, ref, s) : null),
                  _Action('编辑课程', Icons.tune,
                      () => editCourse(context, ref, setId, data, s)),
                ],
              )
            else if (isOneOff)
              _actionRow(
                context,
                [
                  _Action('编辑', Icons.edit_outlined,
                      () => editOneOff(context, ref, setId, data, s)),
                  _Action('删除', Icons.delete_outline,
                      () => _deleteOneOff(context, ref, s),
                      destructive: true),
                ],
              )
            else ...[
              _groupLabel(context, '这一次课（只影响这一天）'),
              const SizedBox(height: 6),
              _actionRow(
                context,
                [
                  _Action('改期', Icons.event_repeat,
                      () => _reschedule(context, ref, data, s)),
                  _Action('停课一次', Icons.event_busy,
                      () => _cancelOnce(ref, s)),
                  _Action('撤销调整', Icons.undo, canUndo ? () => _undo(ref, s) : null),
                ],
              ),
              const SizedBox(height: 14),
              _groupLabel(context, '整门课（影响本学期全部周次）'),
              const SizedBox(height: 6),
              _actionRow(
                context,
                [
                  _Action('编辑课程', Icons.tune,
                      () => editCourse(context, ref, setId, data, s)),
                  _Action('删除课程', Icons.delete_outline,
                      () => _deleteCourse(context, ref, setId, courseTitle),
                      destructive: true),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 在最新的解析结果里找回「同一节课」。
  ///
  /// 认的是「哪条规则的哪一天」（`ruleId` + 未平移的 `originalDate`），
  /// 而不是日期或时间 —— 改期会改的正是后者，用它们当键会在改完之后找不到人。
  /// 单次事件同理，认 `oneOffId`。
  ResolvedSession? _fresh(CalendarSetData data) {
    final all = resolveSessions(
      shifts: data.shifts,
      templates: data.templates,
      oneOffs: data.oneOffs,
      overrides: data.overrides,
    ).sessions;

    for (final s in all) {
      if (session.oneOffId != null) {
        if (s.oneOffId == session.oneOffId) return s;
      } else if (s.ruleId == session.ruleId &&
          s.originalDate != null &&
          session.originalDate != null &&
          isSameDay(s.originalDate!, session.originalDate!)) {
        return s;
      }
    }
    // 整门课被删掉之后就找不到了 —— 此时面板也没必要继续开着。
    return null;
  }

  /// 这条课程规律自己的课程名；找不到规则（单次事件）就退回 [s] 的名字。
  static String _templateTitle(CalendarSetData data, ResolvedSession s) {
    for (final t in data.templates) {
      if (t.id == s.ruleId) return t.title;
    }
    return s.title;
  }

  // ---- 单次调整 ------------------------------------------------------------

  Future<void> _reschedule(
    BuildContext context,
    WidgetRef ref,
    CalendarSetData data,
    ResolvedSession s,
  ) async {
    final picked = await showDialog<_Reschedule>(
      context: context,
      builder: (_) => _RescheduleDialog(
        initials: s,
        shifts: data.shifts,
      ),
    );
    if (picked == null || !context.mounted) return;

    final repo = ref.read(repositoryProvider);
    await repo.setOverride(
      s.ruleId!,
      OverrideData(
        ruleId: s.ruleId!,
        // 匹配键是**未平移**的原始日期，所以这里用 s.originalDate 而不是 s.date
        originalDate: s.originalDate!,
        // 用户选的是「界面上看到的那天」，落库前要换算回套内本地日期
        newDate: toLocalSetDate(picked.date, data.shifts),
        newStartMinute: picked.startMinute,
        newEndMinute: picked.endMinute,
      ),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('这一次课已改期')));
  }

  Future<void> _cancelOnce(WidgetRef ref, ResolvedSession s) => ref
      .read(repositoryProvider)
      .setOverride(
        s.ruleId!,
        OverrideData(
          ruleId: s.ruleId!,
          originalDate: s.originalDate!,
          cancelled: true,
        ),
      );

  Future<void> _undo(WidgetRef ref, ResolvedSession s) => ref
      .read(repositoryProvider)
      .clearOverride(s.ruleId!, s.originalDate!);

  Future<void> _undoAndClose(
    BuildContext context,
    WidgetRef ref,
    ResolvedSession s,
  ) async {
    await _undo(ref, s);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  // ---- 结构性修改 ----------------------------------------------------------

  /// 整门删除 —— 按**课程名**删，一门课名下的全部排课规则一起走。
  ///
  /// 这里原来是 `deleteRule(s.ruleId)`，只删点进来的那一天那条规则。而确认框
  /// 上写的是「这门课的全部周次一起删掉」，按钮也写着「删除课程」—— 用户确认了
  /// 一句不会被兑现的话，周五的课还留在网格上。粒度对齐之后这句话才是真的。
  ///
  /// 传 [title] 而不是从 [s] 取：`s.title` 可能是「单次改名」覆盖后的名字，
  /// 拿它去匹配规则名会一条都对不上。
  Future<void> _deleteCourse(
    BuildContext context,
    WidgetRef ref,
    int setId,
    String title,
  ) async {
    final ok = await _confirm(
      context,
      title: '删除「$title」？',
      body: '这会把本学期这门课的全部周次一起删掉，不只是这一次。'
          '想只去掉一次请用「停课一次」。',
    );
    if (!ok || !context.mounted) return;
    await ref.read(repositoryProvider).deleteCourse(setId, title);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _deleteOneOff(
    BuildContext context,
    WidgetRef ref,
    ResolvedSession s,
  ) async {
    final ok = await _confirm(context, title: '删除「${s.title}」？', body: '这条单次事件将被移除。');
    if (!ok || !context.mounted) return;
    await ref.read(repositoryProvider).deleteOneOff(s.oneOffId!);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  // ---- 小部件 --------------------------------------------------------------

  static Widget _groupLabel(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.outline,
        ),
      );

  /// 三个按钮平分一行。内边距和字号都压到最小 —— 默认的
  /// `OutlinedButton` 内边距在 1/3 屏宽里放不下「停课一次」四个字，
  /// 会折成两行把整排按钮顶高一截。
  static Widget _actionRow(BuildContext context, List<_Action> actions) => Row(
        children: [
          for (final a in actions)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: OutlinedButton.icon(
                  onPressed: a.onPressed,
                  icon: Icon(a.icon, size: 16),
                  label: Text(
                    a.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: a.destructive
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            ),
        ],
      );

  static Widget _detail(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );

  static String _dateLine(ResolvedSession s) {
    final d = s.date;
    final md =
        '${d.year}-${_pad(d.month)}-${_pad(d.day)}  周${_cn(s.weekday)}';
    final period = s.startPeriod == null
        ? ''
        : '  ${periodLabel(s.startPeriod!, s.endPeriod ?? s.startPeriod!)}';
    final week = s.week > 0 ? '  第 ${s.week} 周' : '';
    return '$md$period$week';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _cn(int w) => const ['一', '二', '三', '四', '五', '六', '日'][w - 1];
}

class _Action {
  const _Action(this.label, this.icon, this.onPressed, {this.destructive = false});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;
}

/// 改期对话框选出来的目标。
class _Reschedule {
  const _Reschedule(this.date, this.startMinute, this.endMinute);
  final DateTime date;
  final int startMinute;
  final int endMinute;
}

class _RescheduleDialog extends StatefulWidget {
  const _RescheduleDialog({required this.initials, required this.shifts});

  final ResolvedSession initials;
  final SetShifts shifts;

  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  late DateTime _date = widget.initials.date;
  late int _period = widget.initials.startPeriod ?? kPeriodSlots.first.startPeriod;

  @override
  Widget build(BuildContext context) {
    final slot = slotForStartPeriod(_period);
    return AlertDialog(
      title: const Text('改期'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.event, size: 18),
            label: Text('${_date.year}-${_pad(_date.month)}-${_pad(_date.day)}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(_date.year - 1),
                lastDate: DateTime(_date.year + 2),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _period,
            decoration: const InputDecoration(labelText: '调到第几节'),
            items: [
              for (final s in kPeriodSlots)
                DropdownMenuItem(
                  value: s.startPeriod,
                  child: Text(
                    '${periodLabel(s.startPeriod, s.endPeriod)}'
                    '  ${formatMinutes(s.startMinute)}-${formatMinutes(s.endMinute)}',
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _period = v);
            },
          ),
          if (slot != null) ...[
            const SizedBox(height: 10),
            Text(
              '这一次课将改到 $_dateText ${formatMinutes(slot.startMinute)}'
              '–${formatMinutes(slot.endMinute)}，'
              '其余周次不受影响。',
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final s = slotForStartPeriod(_period);
            if (s == null) return;
            Navigator.of(context).pop(_Reschedule(_date, s.startMinute, s.endMinute));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  String get _dateText => '${_date.month} 月 ${_date.day} 日';

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

/// 二次确认。破坏性操作都走它 —— 课表是攒了一学期的东西，误删的代价不小。
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
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
    ) ??
    false;
