/// 「整体平移」控制面板。
///
/// 为什么做成每按一下立刻写库、而不是「调好再确定」：平移的值就是个整数，
/// 用户真正的判断依据是**网格跟着动起来之后对不对**。攒在对话框里点确定，
/// 等于让人闭着眼睛调。立即生效 + 一个显眼的撤销按钮，反而更省事也更好收回。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/model/resolve.dart';

Future<void> showShiftSheet(
  BuildContext context,
  WidgetRef ref,
  int setId,
) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ShiftSheet(setId: setId),
    );

class _ShiftSheet extends ConsumerWidget {
  const _ShiftSheet({required this.setId});

  final int setId;

  /// 一次按多少分钟。10 分钟够细，又不至于为了挪半小时要点三次。
  static const int _minuteStep = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shifts = ref.watch(setDataProvider(setId)).value?.shifts;
    if (shifts == null) return const SizedBox.shrink();

    final repo = ref.read(repositoryProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('整体平移', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '这个日程的全部课程一起挪动。改期、停课这类单独调整不受影响，'
              '平移量随时可以一键归零。',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            _Row(
              label: '按周',
              value: shifts.weekShift,
              unit: '周',
              onMinus: () => repo.shiftSet(setId, addWeeks: -1),
              onPlus: () => repo.shiftSet(setId, addWeeks: 1),
            ),
            const SizedBox(height: 8),
            _Row(
              label: '按分钟',
              value: shifts.timeShiftMinutes,
              unit: '分钟',
              step: _minuteStep,
              onMinus: () => repo.shiftSet(setId, addMinutes: -_minuteStep),
              onPlus: () => repo.shiftSet(setId, addMinutes: _minuteStep),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    shifts.weekShift == 0 && shifts.timeShiftMinutes == 0
                        ? '当前没有任何平移'
                        : '当前：${_describe(shifts)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                TextButton.icon(
                  onPressed: shifts.weekShift == 0 && shifts.timeShiftMinutes == 0
                      ? null
                      : () => repo.resetShift(setId),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('撤销全部平移'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(SetShifts s) {
    final parts = <String>[
      if (s.weekShift != 0) '${s.weekShift > 0 ? '后移' : '前移'} ${s.weekShift.abs()} 周',
      if (s.timeShiftMinutes != 0)
        '${s.timeShiftMinutes > 0 ? '后移' : '前移'} ${s.timeShiftMinutes.abs()} 分钟',
    ];
    return parts.join('、');
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    this.step = 1,
  });

  final String label;
  final int value;
  final String unit;
  final int step;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label)),
        IconButton.filledTonal(
          onPressed: onMinus,
          icon: const Icon(Icons.remove),
          tooltip: '前移 $step $unit',
        ),
        Expanded(
          child: Center(
            child: Text(
              value == 0 ? '未平移' : '${value > 0 ? '+' : ''}$value $unit',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: value == 0 ? scheme.outline : scheme.primary,
              ),
            ),
          ),
        ),
        IconButton.filledTonal(
          onPressed: onPlus,
          icon: const Icon(Icons.add),
          tooltip: '后移 $step $unit',
        ),
      ],
    );
  }
}
