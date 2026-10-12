/// 课程与单次事件的编辑表单。
///
/// 表单直接收 `CalendarSetData`（而不是去读 provider）是有意的：调用方
/// 多半是从一个 `ResolvedSession` 点进来的，它已经握有那份数据，
/// 再 watch 一次只会让「弹窗内容」和「点进来的那节课」可能对不上。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/settings_providers.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/course_colors.dart';
import '../../core/time/periods.dart';
import '../../data/model/resolve.dart';

/// 周次选择的范围下界：即使这份课表只排到第 12 周，也让用户能选到第 18 周 ——
/// 补排的课可能落在更后面，把上限卡死在现有数据上会让人加不了。
const int _minWeekChoices = 18;

// ---------------------------------------------------------------------------
// 课程（规律性排课）
// ---------------------------------------------------------------------------

/// 编辑一门已存在的课。改动作用于整学期。
Future<void> editCourse(
  BuildContext context,
  WidgetRef ref,
  int setId,
  CalendarSetData data,
  ResolvedSession s,
) async {
  final tpl = data.templates.where((t) => t.id == s.ruleId).firstOrNull;
  if (tpl == null) return;
  await _openCourseForm(context, ref, setId, data, existing: tpl);
}

/// 同名的另一条排课规则已有的颜色；没有就给 null。
///
/// 新建一条排课时用它来**继承**这门课的颜色：不继承的话，给一门已经改过色的课
/// 加一个时段，新时段会按课程名哈希拿回自动色，跟老时段对不上 —— 加一节课
/// 反而把配色弄花了。
String? _inheritedColor(CalendarSetData data, String title, int? exceptRuleId) {
  for (final t in data.templates) {
    // 只认已经指定过颜色的那条：同为 null（都还是自动色）不算「继承到了」。
    if (t.title == title && t.id != exceptRuleId && t.colorHex != null) {
      return t.colorHex;
    }
  }
  return null;
}

/// 新增一门课。
///
/// 从空格子点进来时带上 [weekday] / [startPeriod]，表单预填好那一格；
/// 从「新增」按钮进来时两个都不带，星期、节次留给用户在表单里自己选 ——
/// 这时**不要**编一个默认格子塞进去，预填的星期节次看起来就像是用户自己选的。
Future<void> addCourse(
  BuildContext context,
  WidgetRef ref,
  int setId,
  CalendarSetData data, {
  int? weekday,
  int? startPeriod,
}) =>
    _openCourseForm(
      context,
      ref,
      setId,
      data,
      initials: (weekday == null || startPeriod == null)
          ? null
          : (
              weekday: weekday,
              startPeriod: startPeriod,
              endPeriod:
                  slotForStartPeriod(startPeriod)?.endPeriod ?? startPeriod,
            ),
    );

Future<void> _openCourseForm(
  BuildContext context,
  WidgetRef ref,
  int setId,
  CalendarSetData data, {
  CourseTemplate? existing,
  ({int weekday, int startPeriod, int endPeriod})? initials,
}) async {
  final result = await showDialog<CourseTemplate>(
    context: context,
    builder: (_) => _CourseForm(
      existing: existing,
      initials: initials,
      weekChoices: _weekChoices(data),
      // 新增时要给一个能落库的新 id：新增用 0（入库后由数据库分配），
      // 编辑则沿用原 id。
      editing: existing != null,
      inheritedColor: (title) =>
          _inheritedColor(data, title, existing?.id),
      // 「跟随默认（N 分钟）」显示的是**这个日程**实际会用的那个数：本日程有
      // 覆盖就用覆盖的，否则才是全局的。一直取全局那个数的话，一个自定义过提前量
      // 的日程里，这门课会显示一个**不是它真正会用的**数字 —— 用户照着它调时间，
      // 提醒却在另一个时刻响。算法必须和 `buildReminderPlan` 里日程层那一级是
      // 同一份，所以走 `AppSettings.leadMinutesFor`，不在这里重新拼一遍。
      defaultLeadMinutes: ref.read(settingsProvider).leadMinutesFor(setId),
    ),
  );
  if (result == null || !context.mounted) return;

  final repo = ref.read(repositoryProvider);
  if (existing == null) {
    await repo.addRule(setId, result);
  } else {
    await repo.updateRule(setId, result);
  }

  // 改色是**课程级**的：同名规则一起刷。只写点进来的这一条，会让同一门课在
  // 网格上出现两种颜色 —— 而「同一门课永远同色」正是这套配色的意义所在。
  //
  // 改了课程名就不刷：改名之后「这门课」指向的规则集合已经变了，按新名字刷色
  // 会误伤原本就叫这个名字的另一门课。此时这一条的颜色已经随 updateRule 落库。
  if (existing == null || existing.title == result.title) {
    await repo.setCourseColor(setId, result.title, result.colorHex);
  }
}

/// 可选周次的上界：取已有数据的最大值，但不低于 [_minWeekChoices]。
int _weekChoices(CalendarSetData data) {
  var maxWeek = _minWeekChoices;
  for (final t in data.templates) {
    for (final w in t.weeks) {
      if (w > maxWeek) maxWeek = w;
    }
  }
  // 留几周的余量，便于补排到学期末之后
  return maxWeek + 2;
}

class _CourseForm extends StatefulWidget {
  const _CourseForm({
    required this.weekChoices,
    required this.editing,
    required this.inheritedColor,
    required this.defaultLeadMinutes,
    this.existing,
    this.initials,
  });

  final int weekChoices;
  final bool editing;
  final CourseTemplate? existing;
  final ({int weekday, int startPeriod, int endPeriod})? initials;

  /// 全局默认提前量，用于把「跟随默认」这一档写清楚是几分钟。
  final int defaultLeadMinutes;

  /// 同名的另一条排课规则已有的颜色，用来在「自动」模式下预览真正会用的色。
  final String? Function(String title) inheritedColor;

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _teacher =
      TextEditingController(text: widget.existing?.teacher ?? '');
  late final _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  late int _weekday = widget.existing?.weekday ?? widget.initials?.weekday ?? 1;
  late int _startPeriod =
      widget.existing?.startPeriod ?? widget.initials?.startPeriod ?? 1;
  late int _endPeriod =
      widget.existing?.endPeriod ?? widget.initials?.endPeriod ?? 2;
  late Set<int> _weeks = {
    ...(widget.existing?.weeks ??
        List.generate(widget.weekChoices, (i) => i + 1)),
  };

  /// 手动指定的课程颜色；null 表示「按课程名自动配色」。
  late String? _colorHex = widget.existing?.colorHex;

  /// 用户在这一次编辑里**主动点过**色块没有。
  ///
  /// 光看 `_colorHex == null` 分不清「没动过、还是自动色」和「主动选回了自动」。
  /// 前者要继承这门课现有的颜色，后者要真的把整门课恢复成自动配色 ——
  /// 两者写进去的值都是 null，但意图相反，只能另外记一笔。
  bool _colorTouched = false;

  late bool _remindersEnabled = widget.existing?.remindersEnabled ?? true;

  /// 这门课的提前量；null 表示跟随设置页里的全局默认。
  late int? _leadMinutes = widget.existing?.leadMinutes;

  /// 保存时真正会落库的颜色。
  ///
  /// 没主动改过就沿用这门课已有的颜色（编辑别的字段不该顺手把颜色重置回自动），
  /// 这门课还没指定过颜色时就是 null，也就是自动配色。
  String? get _effectiveColorHex => _colorTouched
      ? _colorHex
      : (widget.existing?.colorHex ?? widget.inheritedColor(_title.text.trim()));

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in [_title, _teacher, _location, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startSlot = slotForStartPeriod(_startPeriod);
    return AlertDialog(
      title: Text(widget.editing ? '编辑课程' : '新增课程'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '课程名'),
                  // 重建一次，让下面「自动」色块跟着课程名走 —— 否则预览一直停在
                  // 打开对话框时的那个名字，「同名同色」这件事就看不出来。
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '课程名不能为空' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _teacher,
                  decoration: const InputDecoration(labelText: '教师'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(labelText: '地点'),
                ),
                const SizedBox(height: 12),
                _label(context, '星期'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      ChoiceChip(
                        selected: _weekday == d,
                        label: Text(const ['一', '二', '三', '四', '五', '六', '日'][d - 1]),
                        onSelected: (_) => setState(() => _weekday = d),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _startPeriod,
                        decoration: const InputDecoration(labelText: '起始节'),
                        items: [
                          for (final s in kPeriodSlots)
                            DropdownMenuItem(
                              value: s.startPeriod,
                              child: Text('第 ${s.startPeriod} 节'),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _startPeriod = v;
                            _endPeriod = slotForStartPeriod(v)!.endPeriod;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _endPeriod,
                        decoration: const InputDecoration(labelText: '结束节'),
                        items: [
                          // 结束节次可以跨大节（1-4 节连堂），所以从起始节开始列到 10
                          for (var p = _startPeriod; p <= kPeriodSlots.last.endPeriod; p++)
                            DropdownMenuItem(value: p, child: Text('第 $p 节')),
                        ],
                        onChanged: (v) => setState(() => _endPeriod = v ?? _endPeriod),
                      ),
                    ),
                  ],
                ),
                if (startSlot != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '时间：${formatMinutes(startSlot.startMinute)}'
                    ' – ${formatMinutes(slotForPeriod(_endPeriod)?.endMinute ?? startSlot.endMinute)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    _label(context, '上课周次'),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(
                          () => _weeks = {for (var i = 1; i <= widget.weekChoices; i++) i}),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setState(_weeks.clear),
                      child: const Text('清空'),
                    ),
                  ],
                ),
                if (_weeks.isEmpty)
                  Text(
                    '一周都没选 —— 保存后这门课不会出现在课表上',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Wrap(
                  spacing: 5,
                  runSpacing: 2,
                  children: [
                    for (var w = 1; w <= widget.weekChoices; w++)
                      FilterChip(
                        selected: _weeks.contains(w),
                        label: Text('$w', style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onSelected: (on) => setState(() {
                          if (on) {
                            _weeks.add(w);
                          } else {
                            _weeks.remove(w);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _CourseColorField(
                  title: _title.text.trim(),
                  hex: _effectiveColorHex,
                  onChanged: (h) => setState(() {
                    _colorHex = h;
                    _colorTouched = true;
                  }),
                ),
                const SizedBox(height: 12),
                _CourseReminderField(
                  enabled: _remindersEnabled,
                  leadMinutes: _leadMinutes,
                  defaultLeadMinutes: widget.defaultLeadMinutes,
                  onEnabledChanged: (v) => setState(() => _remindersEnabled = v),
                  onLeadChanged: (v) => setState(() => _leadMinutes = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: '备注'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final title = _title.text.trim();
            final weeks = _weeks.toList()..sort();
            Navigator.of(context).pop(
              CourseTemplate(
                id: widget.existing?.id ?? 0,
                title: title,
                weekday: _weekday,
                startPeriod: _startPeriod,
                endPeriod: _endPeriod,
                weeks: weeks,
                teacher: _teacher.text.trim(),
                location: _location.text.trim(),
                note: _note.text.trim(),
                colorHex: _effectiveColorHex,
                remindersEnabled: _remindersEnabled,
                leadMinutes: _leadMinutes,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  static Widget _label(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
}

/// 单门课的提醒设置。
///
/// 这里**只有覆盖，没有第二份默认值**：不动它就是「跟随设置页里的那个数字」，
/// 而不是把当时的全局默认抄一份存下来。抄下来的话，用户后来把全局默认从
/// 15 分钟改成 10 分钟，所有编辑过的课会静静地停在 15 分钟上，
/// 而界面上没有任何地方能看出这件事。
class _CourseReminderField extends StatelessWidget {
  const _CourseReminderField({
    required this.enabled,
    required this.leadMinutes,
    required this.defaultLeadMinutes,
    required this.onEnabledChanged,
    required this.onLeadChanged,
  });

  final bool enabled;

  /// null = 跟随默认。
  final int? leadMinutes;
  final int defaultLeadMinutes;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int?> onLeadChanged;

  static const List<int> _presets = [5, 10, 15, 20, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 全局默认那一档已经从预设里出现过一次了，再列一遍会出现两个 15 分钟，
    // 分不清哪个才是「跟随默认」。
    final presets = _presets.where((m) => m != defaultLeadMinutes);
    final custom = leadMinutes != null && !_presets.contains(leadMinutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.alarm, size: 16, color: scheme.outline),
            const SizedBox(width: 6),
            Text(
              '课前提醒',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.outline,
              ),
            ),
            const Spacer(),
            Switch(value: enabled, onChanged: onEnabledChanged),
          ],
        ),
        if (enabled)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: Text('跟随默认（$defaultLeadMinutes 分钟）'),
                selected: leadMinutes == null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) => onLeadChanged(null),
              ),
              for (final m in presets)
                ChoiceChip(
                  label: Text('$m 分钟'),
                  selected: leadMinutes == m,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => onLeadChanged(m),
                ),
              ChoiceChip(
                label: Text(custom ? '提前 $leadMinutes 分钟' : '自定义…'),
                selected: custom,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) => _pickCustom(context),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final controller =
        TextEditingController(text: (leadMinutes ?? defaultLeadMinutes).toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('这门课提前多久'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '分钟', suffixText: '分钟'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (value == null) return;
    onLeadChanged(value.clamp(0, AppSettings.kMaxLeadMinutes));
  }
}

/// 给一门课挑颜色。
///
/// 默认是「自动」—— 按课程名哈希取色，同一门课在网格上永远同色。手动指定
/// 是例外而非常态，所以排在最前面的是「自动」，而不是一上来就摆一排色块
/// 逼人做选择。
///
/// 色板用 [kCoursePalette]（偏深、能压白字），不是主题色那套 —— 网格块的
/// 底色要跟文字有对比度，主题色是给界面用的，两者要求正好相反。
class _CourseColorField extends StatelessWidget {
  const _CourseColorField({
    required this.title,
    required this.hex,
    required this.onChanged,
  });

  /// 用来在「自动」模式下预览这门课实际会拿到哪个颜色。
  final String title;
  final String? hex;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auto = courseColor(title);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '颜色',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.outline,
              ),
            ),
            const SizedBox(width: 6),
            // 作用范围写在标题这一行，而不是色块下面另起一行：对话框里内容
            // 是可滚动的，色块下面那行常常正好落在折线以下 —— 一句没人看得见的
            // 说明等于没写。
            Text(
              '整门课共用',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const Spacer(),
            Text(
              hex == null ? '自动' : hex!,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 「自动」这一项显示的正是自动会取到的那个色，选与不选一眼可辨
            _Swatch(
              color: auto,
              selected: hex == null,
              icon: Icons.auto_awesome,
              onTap: () => onChanged(null),
            ),
            for (final c in kCoursePalette)
              _Swatch(
                color: c,
                selected: hex != null && parseHexColor(hex) == c,
                onTap: () => onChanged(toHexColor(c)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon = Icons.check,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Tooltip(
          message: toHexColor(color),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              // 选中的圈画在外面，不占色块本身的面积 ——
              // 画在里面会让色块的可见大小随选中状态变化
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 2.5,
                    )
                  : null,
            ),
            child: selected
                ? Icon(icon, size: 15, color: onCourseColor(color))
                : null,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// 单次事件
// ---------------------------------------------------------------------------

/// 新增一条单次事件。
Future<void> addOneOff(
  BuildContext context,
  WidgetRef ref,
  int setId,
  CalendarSetData data, {
  DateTime? date,
}) async {
  final result = await showDialog<OneOffData>(
    context: context,
    builder: (_) => _OneOffForm(
      // 默认落在「今天」在界面上显示的那一天；落库前再换算回套内本地日期
      initialDate: date ?? DateTime.now(),
      onLocalize: (shown) => toLocalSetDate(shown, data.shifts),
    ),
  );
  if (result == null || !context.mounted) return;
  await ref.read(repositoryProvider).addOneOff(setId, result);
}

/// 编辑一条已存在的单次事件。
Future<void> editOneOff(
  BuildContext context,
  WidgetRef ref,
  int setId,
  CalendarSetData data,
  ResolvedSession s,
) async {
  final existing =
      data.oneOffs.where((e) => e.id == s.oneOffId).firstOrNull;
  if (existing == null) return;

  final result = await showDialog<OneOffData>(
    context: context,
    builder: (_) => _OneOffForm(
      existing: existing,
      initialDate: fromLocalSetDate(existing.date, data.shifts),
      onLocalize: (shown) => toLocalSetDate(shown, data.shifts),
    ),
  );
  if (result == null || !context.mounted) return;
  await ref.read(repositoryProvider).updateOneOff(setId, result);
}

class _OneOffForm extends StatefulWidget {
  const _OneOffForm({
    required this.initialDate,
    required this.onLocalize,
    this.existing,
  });

  final OneOffData? existing;

  /// 表单里显示的日期（含平移）。
  final DateTime initialDate;

  /// 显示日期 → 套内本地日期。落库前必过。
  final DateTime Function(DateTime) onLocalize;

  @override
  State<_OneOffForm> createState() => _OneOffFormState();
}

class _OneOffFormState extends State<_OneOffForm> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _date = widget.initialDate;
  late TimeOfDay _start = _tod(widget.existing?.startMinute ?? 8 * 60);
  late TimeOfDay _end = _tod(widget.existing?.endMinute ?? 9 * 60 + 40);

  final _formKey = GlobalKey<FormState>();

  static TimeOfDay _tod(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  @override
  void dispose() {
    for (final c in [_title, _location, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新增事件' : '编辑事件'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '标题'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '标题不能为空' : null,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                      '${_date.year}-${_two(_date.month)}-${_two(_date.day)}'),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text('开始 ${_start.format(context)}'),
                        onPressed: () async {
                          final t = await showTimePicker(
                              context: context, initialTime: _start);
                          if (t != null) setState(() => _start = t);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text('结束 ${_end.format(context)}'),
                        onPressed: () async {
                          final t = await showTimePicker(
                              context: context, initialTime: _end);
                          if (t != null) setState(() => _end = t);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(labelText: '地点'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: '备注'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              OneOffData(
                id: widget.existing?.id ?? 0,
                title: _title.text.trim(),
                // 只有这里把界面日期换算回套内本地日期；其余字段与平移无关
                date: widget.onLocalize(_date),
                startMinute: _start.hour * 60 + _start.minute,
                endMinute: _end.hour * 60 + _end.minute,
                location: _location.text.trim(),
                note: _note.text.trim(),
                colorHex: widget.existing?.colorHex,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
