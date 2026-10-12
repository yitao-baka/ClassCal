/// 导入向导 —— 解析完之后、真正落库之前的那一步。
///
/// 它要在一屏里说清三件事，缺一件用户就得靠猜：
///
/// 1. **解析出了什么**（几门课、哪些周、有没有没认出来的条目）；
/// 2. **第 1 周的周一是哪天** —— ICS 里不含年份，这个只能靠推或问，
///    而差一周会让整张课表错位；
/// 3. **落到哪里** —— 新建一个标签页，还是并进已有的某一套。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/time/periods.dart';
import '../../data/db/database.dart';
import '../../data/import/ics_import.dart';

/// 向导选定的落库方式。
sealed class ImportTarget {
  const ImportTarget();
}

/// 新建一个标签页。
class NewTab extends ImportTarget {
  const NewTab();
}

/// 并进 [setId] 那一套。
class MergeInto extends ImportTarget {
  const MergeInto(this.setId);
  final int setId;
}

/// 向导的结果。[target] 为 null 表示用户取消；[anchor] 是重新解析用的锚点。
class ImportPlan {
  const ImportPlan({
    required this.target,
    required this.anchor,
    required this.name,
  });

  final ImportTarget? target;
  final DateTime anchor;

  /// 新建标签页时的名字。合并时用不上（沿用目标那一套的名字）。
  final String name;
}

/// 打开向导。返回 null 表示用户取消。
///
/// [reparse] 是「换了锚点之后重新解析」的回调 —— 向导不自己调 `importIcs`，
/// 免得把 ICS 解析器和 UI 搅在一起，也免得向导还得知道源文本长什么样。
Future<ImportPlan?> showImportWizard(
  BuildContext context, {
  required IcsImportResult initial,
  required String sourceName,
  required IcsImportResult Function(DateTime anchor) reparse,
}) =>
    showDialog<ImportPlan>(
      context: context,
      builder: (_) => _ImportWizard(
        initial: initial,
        sourceName: sourceName,
        reparse: reparse,
      ),
    );

class _ImportWizard extends ConsumerStatefulWidget {
  const _ImportWizard({
    required this.initial,
    required this.sourceName,
    required this.reparse,
  });

  final IcsImportResult initial;
  final String sourceName;
  final IcsImportResult Function(DateTime anchor) reparse;

  @override
  ConsumerState<_ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends ConsumerState<_ImportWizard> {
  late IcsImportResult _result = widget.initial;
  late DateTime _anchor = widget.initial.week1Monday;
  ImportTarget _target = const NewTab();
  late final _nameController = TextEditingController(text: _defaultName);

  String get _defaultName {
    final base = widget.sourceName.replaceAll(RegExp(r'\.(ics|json)$'), '');
    return base.isEmpty ? '导入的日程' : base;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 换锚点：周次是按锚点算出来的，必须整份重新归并。
  void _reanchor(DateTime anchor) {
    setState(() {
      _anchor = anchor;
      _result = widget.reparse(anchor);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(tabRowsProvider).value ?? const <CalendarSet>[];
    final stats = _Stats.of(_result);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('导入课表'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('识别到 ${stats.courseCount} 门课程'
                  '${stats.weeks.isEmpty ? '' : '，第 ${stats.weeks.first}-${stats.weeks.last} 周'}'),
              const SizedBox(height: 4),
              Text(
                '共 ${_result.eventCount} 次上课'
                '${stats.oneOffCount == 0 ? '' : '，其中 ${stats.oneOffCount} 条按单次事件处理'}',
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),

              const SizedBox(height: 16),
              _section(context, '学期起始'),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit_calendar, size: 18),
                label: Text('第 1 周周一：${_ymd(_anchor)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _anchor,
                    firstDate: DateTime(_anchor.year - 2),
                    lastDate: DateTime(_anchor.year + 2),
                  );
                  // 锚点定义上必须是周一，选了别的日子就落到它所在周的周一
                  if (picked != null) {
                    _reanchor(picked.subtract(Duration(days: picked.weekday - 1)));
                  }
                },
              ),
              if (_result.week1Inferred)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '文件里没有写明这一项，上面是推算结果 —— 日期不对请改。',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),

              const SizedBox(height: 16),
              _section(context, '导入到哪里'),
              RadioGroup<ImportTarget>(
                groupValue: _target,
                onChanged: (v) => setState(() => _target = v ?? const NewTab()),
                child: Column(
                  children: [
                    const RadioListTile<ImportTarget>(
                      value: NewTab(),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('新建一个日程'),
                    ),
                    if (tabs.isNotEmpty)
                      RadioListTile<ImportTarget>(
                        value: MergeInto(tabs.first.id),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('合并到已有日程'),
                      ),
                    if (_target is MergeInto && tabs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 4),
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: (_target as MergeInto).setId,
                          items: [
                            for (final t in tabs)
                              DropdownMenuItem(value: t.id, child: Text(t.name)),
                          ],
                          onChanged: (v) => setState(
                              () => _target = MergeInto(v ?? tabs.first.id)),
                        ),
                      ),
                    if (tabs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '还没有别的日程可以合并。',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ),
                  ],
                ),
              ),
              if (_target is MergeInto) _mergeHint(context, tabs),
              if (_target is NewTab) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '日程名称',
                    isDense: true,
                  ),
                ),
              ],

              if (_result.warnings.isNotEmpty) _warnings(context),
            ],
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
            final name = _nameController.text.trim();
            Navigator.of(context).pop(
              ImportPlan(
                target: _target,
                anchor: _anchor,
                name: name.isEmpty ? _defaultName : name,
              ),
            );
          },
          child: const Text('导入'),
        ),
      ],
    );
  }

  /// 合并到某一套时，锚点不一致是个必须说清的坑：周次是相对锚点算的，
  /// 两套锚点不同却并在一起，同一门课会凭空错开若干周。
  Widget _mergeHint(BuildContext context, List<CalendarSet> tabs) {
    final targetId = (_target as MergeInto).setId;
    final target = tabs.where((t) => t.id == targetId).firstOrNull;
    if (target == null) return const SizedBox.shrink();

    final same = isSameDay(target.week1Monday, _anchor);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            same ? Icons.info_outline : Icons.warning_amber_rounded,
            size: 16,
            color: same ? scheme.outline : scheme.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              same
                  ? '与「${target.name}」的第 1 周周一一致，周次能对得上。'
                  : '注意：「${target.name}」的第 1 周是 ${_ymd(target.week1Monday)}，'
                      '与这次的 ${_ymd(_anchor)} 不同。两者周次含义不一样，'
                      '合并后可能整体错开。',
              style: TextStyle(
                fontSize: 12,
                color: same ? scheme.outline : scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warnings(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(context, '解析提示（${_result.warnings.length}）'),
          const SizedBox(height: 4),
          // 警告不弹窗打断，但必须让人看得见 ——
          // 「有 3 条事件没认出来」是会影响正确性的信息，藏起来就是骗人。
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 110),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in _result.warnings.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('· $w', style: const TextStyle(fontSize: 12)),
                    ),
                  if (_result.warnings.length > 12)
                    Text('…还有 ${_result.warnings.length - 12} 条',
                        style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _section(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.outline,
        ),
      );

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 预览用的统计量。
class _Stats {
  const _Stats({required this.courseCount, required this.weeks, required this.oneOffCount});

  final int courseCount;
  final List<int> weeks;
  final int oneOffCount;

  factory _Stats.of(IcsImportResult r) {
    final weeks = <int>{};
    for (final t in r.set.templates) {
      weeks.addAll(t.weeks);
    }
    return _Stats(
      courseCount: r.set.templates.length,
      weeks: weeks.toList()..sort(),
      oneOffCount: r.set.oneOffs.length,
    );
  }
}
