/// 课表周网格 —— 主视图。
///
/// 自绘而不是找现成控件：没有任何维护中的 Dart 3 课表网格包（`timetable` 只有
/// alpha，`*_timetable_view` 已死且不兼容 Dart 3），而课表网格要的东西又相当特殊
/// —— 跨节次合并、按周筛选、同格重叠时分栏、空位点击新增。自己画大约一百行，
/// 换来对这些的全部控制权。
///
/// 布局：行 = 大节，列 = 星期。课程块用 `Positioned` 摆进 `Stack`，
/// 位置由「星期 → 列，节次 → 行」直接算出，不做任何测量。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/course_colors.dart';
import '../../core/time/periods.dart';
import '../../data/model/resolve.dart';

/// 左侧节次栏宽度。
const double _gutterWidth = 54;

/// 表头（星期 + 日期）高度。
const double _headerHeight = 46;

/// 每个大节的**最小**行高。
///
/// 实际行高取「这个值与可用高度/行数中的较大者」：手机竖屏装得下就用撑满的
/// 高度，装不下才退化成滚动。写死行高会让课表下方空出一大块 —— 看起来像
/// 「后面几节没课」，而实际只是没画满。
const double _minRowHeight = 78;

const List<String> _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.sessions,
    required this.week,
    required this.week1Monday,
    this.now,
    this.onTapSession,
    this.onTapEmptySlot,
  });

  /// **仅本周**的课，调用方已经筛过。
  final List<ResolvedSession> sessions;

  final int week;
  final DateTime week1Monday;

  /// 当前时刻；为 null 则不画「现在」指示线。
  final DateTime? now;

  final void Function(ResolvedSession session)? onTapSession;

  /// 点空格子：给出星期与起始节次，供「在此新增」。
  final void Function(int weekday, int startPeriod)? onTapEmptySlot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - _gutterWidth) / 7;

        return Column(
          children: [
            SizedBox(
              height: _headerHeight,
              child: _Header(
                week: week,
                week1Monday: week1Monday,
                cellWidth: cellWidth,
                now: now,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              // 行高要按**滚动区自己的**高度算，所以 LayoutBuilder 必须放在
              // Expanded 里面：放外面拿到的是含表头的整块高度，会多算一截。
              child: LayoutBuilder(
                builder: (context, grid) {
                  final rowHeight = math.max(
                    _minRowHeight,
                    grid.maxHeight / kPeriodRowCount,
                  );
                  final placed = _layout(sessions);

                  return SingleChildScrollView(
                    child: SizedBox(
                      height: rowHeight * kPeriodRowCount,
                      child: Stack(
                        children: [
                          _gridLines(cellWidth, rowHeight),
                          // 节次标签画在网格内部而不是外面固定住：它必须跟行一起
                          // 纵向滚动，否则滚下去之后标签和格子对不上。
                          for (var i = 0; i < kPeriodRowCount; i++)
                            Positioned(
                              left: 0,
                              top: i * rowHeight,
                              width: _gutterWidth,
                              height: rowHeight,
                              child: _PeriodLabel(rowIndex: i),
                            ),
                          // 空位也要能点。顺序很关键：空位层必须画在课程块
                          // **前面**，`Stack` 里后画的压在上面、也先吃到点击 ——
                          // 反过来的话每个课程块都被一层透明空位盖住，点不动。
                          ..._emptyCells(context, placed, cellWidth, rowHeight),
                          for (final p in placed)
                            _block(context, p, cellWidth, rowHeight),
                          if (now != null) ..._nowLine(cellWidth, rowHeight),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // 布局计算
  // -------------------------------------------------------------------------

  /// 把课程摆到 (列, 行) 上，并处理同格重叠。
  ///
  /// 同一格里有两门课是真实存在的（不同教师、不同周次、临时并课），
  /// 直接叠在一起会互相盖住，所以横向分栏。
  static List<PlacedSession> _layout(List<ResolvedSession> sessions) =>
      layoutWeekGrid(sessions);

  Widget _gridLines(double cellWidth, double rowHeight) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _GridPainter(
          gutterWidth: _gutterWidth,
          cellWidth: cellWidth,
          rowHeight: rowHeight,
          rows: kPeriodRowCount,
          color: const Color(0x1F000000),
        ),
      ),
    );
  }

  Widget _block(
    BuildContext context,
    PlacedSession p,
    double cellWidth,
    double rowHeight,
  ) {
    final laneWidth = cellWidth / p.lanes;
    final color = courseColor(p.session.title, overrideHex: p.session.colorHex);
    final fg = onCourseColor(color);
    final s = p.session;

    // 单次事件要在块里把**真实钟点**顶到教室前面。
    //
    // 块本身占满整行是网格的粒度决定的（行只有「第几大节」），一个 14:30–14:40
    // 的事件画出来跟一节 90 分钟的课一样高。形状上的这个夸张没法消除，只好用
    // 一句话兜着：看到「14:30-14:40」就知道这块不是那个点次的课。
    final meta = s.oneOffId == null
        ? s.location
        : [
            '${formatMinutes(s.startMinute)}-${formatMinutes(s.endMinute)}',
            if (s.location.isNotEmpty) s.location,
          ].join(' · ');

    // 只有一格宽时不给圆角留太多空隙，否则字会被挤到没地方
    if (s.cancelled) return _ghostBlock(context, p, cellWidth, rowHeight, color);

    return Positioned(
      left: _gutterWidth + p.col * cellWidth + p.lane * laneWidth + 1.5,
      top: p.row * rowHeight + 2,
      width: laneWidth - 3,
      height: p.span * rowHeight - 4,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTapSession == null ? null : () => onTapSession!(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    color: fg,
                    fontSize: 11.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                  // 单次事件少给一行标题：它固定占一行高，省下来的地方让给下面
                  // 那行钟点，否则标题一长就把「14:30-14:40」挤出块外。
                  maxLines: s.oneOffId != null ? 2 : (p.span > 1 ? 5 : 3),
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 10, height: 1.1),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const Spacer(),
                // 被改过一次的课打个角标，提醒「这节跟常规不一样」
                if (s.adjusted)
                  Icon(Icons.edit_calendar, size: 11, color: fg.withValues(alpha: 0.9)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 空格子的点击区 —— 点一下在那儿新增一门课。
  ///
  /// 「这一格有没有被占」要按**跨越的行**算：1-4 节的连堂课占了两行，
  /// 只看起始行的话，它下面那一行的空位点上去会盖出第二门课。
  List<Widget> _emptyCells(
    BuildContext context,
    List<PlacedSession> placed,
    double cellWidth,
    double rowHeight,
  ) {
    if (onTapEmptySlot == null) return const [];

    return [
      for (final slot in freeSlots(placed))
        Positioned(
          left: _gutterWidth + (slot.weekday - 1) * cellWidth,
          top: slot.row * rowHeight,
          width: cellWidth,
          height: rowHeight,
          child: GestureDetector(
            // opaque 是必须的：这个容器本身不画任何东西，默认的
            // deferToChild 会让整块区域点不中。
            behavior: HitTestBehavior.opaque,
            onTap: () => onTapEmptySlot!(slot.weekday, slot.startPeriod),
          ),
        ),
    ];
  }

  /// 被停掉的那一次的「幽灵块」。
  ///
  /// 画成描边空心而不是填色：它表示的是**这节课不上**，填一块实色会被当成
  /// 正常课程扫过去。字保留（划掉）是为了让人认得出停的是哪门课 ——
  /// 只剩一个空框的话，还得去别处查才知道自己停掉了什么。
  Widget _ghostBlock(
    BuildContext context,
    PlacedSession p,
    double cellWidth,
    double rowHeight,
    Color color,
  ) {
    final s = p.session;
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: _gutterWidth + p.col * cellWidth + 1.5,
      top: p.row * rowHeight + 2,
      width: cellWidth - 3,
      height: p.span * rowHeight - 4,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTapSession == null ? null : () => onTapSession!(s),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              color: color.withValues(alpha: 0.06),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: TextStyle(
                    color: scheme.outline,
                    fontSize: 11.5,
                    height: 1.15,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: scheme.outline,
                  ),
                  maxLines: p.span > 1 ? 5 : 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Text(
                  '停课',
                  style: TextStyle(
                    color: scheme.outline,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 「现在」指示线。
  ///
  /// 只在某一节课正在进行时才画 —— 课间和晚上的时间轴是断开的
  /// （行是等高的，但节次之间的空隙不等长），画一条连续的时间线会跟格子对不上，
  /// 反而不如只在有意义的时候出现。
  List<Widget> _nowLine(double cellWidth, double rowHeight) {
    final minute = now!.hour * 60 + now!.minute;
    final x = _nowX(cellWidth);
    if (x == null) return const [];

    for (var i = 0; i < kPeriodSlots.length; i++) {
      final slot = kPeriodSlots[i];
      if (minute >= slot.startMinute && minute <= slot.endMinute) {
        final t = (minute - slot.startMinute) / slot.durationMinutes;
        return [
          Positioned(
            left: _gutterWidth,
            top: i * rowHeight + t * rowHeight,
            width: cellWidth * 7,
            child: const Divider(height: 1, thickness: 1.5, color: Color(0xFFE53935)),
          ),
        ];
      }
    }
    return const [];
  }

  /// 今天是周几就在哪一列画线；不在本周则没有线。
  double? _nowX(double cellWidth) {
    final day = dateOnly(now!);
    final weekMonday = weekMondayOf(week1Monday, week);
    for (var i = 0; i < 7; i++) {
      if (isSameDay(day, weekMonday.add(Duration(days: i)))) return i.toDouble();
    }
    return null;
  }
}

/// 本周周一的日期。
DateTime weekMondayOf(DateTime week1Monday, int week) =>
    dateFor(week1Monday: week1Monday, week: week, weekday: 1);

/// 一个课程块在网格上的落位。
///
/// 抽成公开的纯函数而不是埋在 `build` 里，是为了能直接单元测试：
/// 「第 5 周周三第 3-4 节的课落在第 3 列第 2 行」这种断言比截图比对稳定得多，
/// 也真的能挡住回归。
class PlacedSession {
  const PlacedSession({
    required this.session,
    required this.col,
    required this.row,
    required this.span,
    required this.lane,
    required this.lanes,
  });

  final ResolvedSession session;

  /// 0-based 列（0 = 周一）。
  final int col;

  /// 0-based 行（0 = 第一大节）。
  final int row;

  /// 纵向跨几行。
  final int span;

  /// 同一格内的第几栏、共几栏。
  final int lane;
  final int lanes;
}

/// 计算 [sessions] 在网格上的落位。
///
/// **单次事件也上网格**，靠开始钟点反推落在哪一大节（[rowForMinute]）。这里曾经
/// 把它们一律挡在外面，理由是「网格的行是第几大节，挂不上这个坐标系」——
/// 理由本身没错，但推出的结果是：用户从网格上「新增单次事件」（那一步还特意把
/// 日期预填成他正看着的那一周），存完屏幕上**什么也没多出来**，而且此后没有任何
/// 入口能再点开它。「不该上网格」的那类条目是清早、深夜这种网格根本没画到的钟点，
/// 由 [rowForMinute] 返回 null 挡掉，而不是所有单次事件一起挡。
///
/// 块的样子会夸张：它占满整行（那就是一大节），而实际可能只有十分钟。这个落差
/// 靠块里的文字补 —— 单次事件在网格上显示的是**真实钟点**，见 `_block`。
///
/// 停课的条目单独处理：它们**不参与分栏**，一律占满整格、lane 排在最前面。
/// 若让一节停掉的课参与分栏，同一格里那节真要去上的课会被挤成半栏 ——
/// 为了一个不上的课，牺牲了要上的课的宽度。
List<PlacedSession> layoutWeekGrid(List<ResolvedSession> sessions) {
  // 键用 col*100+row 而不是 'col,row' 字符串：这是一个纯整数坐标，
  // 拼字符串既要分配又要解析，没必要。
  final byCell = <int, List<ResolvedSession>>{};
  final ghosts = <PlacedSession>[];

  for (final s in sessions) {
    final row = s.oneOffId != null
        ? rowForMinute(s.startMinute)
        : rowForStartPeriod(s.startPeriod ?? -1);
    if (row == null) continue;
    // 单次事件没有节次，也就没有「跨几行」可言，一律占一行。
    final span = s.startPeriod == null || s.endPeriod == null
        ? 1
        : rowsSpanned(s.startPeriod!, s.endPeriod!);

    if (s.cancelled) {
      ghosts.add(
        PlacedSession(
          session: s,
          col: s.weekday - 1,
          row: row,
          span: span,
          lane: 0,
          lanes: 1,
        ),
      );
      continue;
    }
    (byCell[(s.weekday - 1) * 100 + row] ??= []).add(s);
  }

  // 幽灵块排在最前 —— `Stack` 后画的盖先画的，让真正要上的课压在上面。
  final out = <PlacedSession>[...ghosts];
  for (final entry in byCell.entries) {
    final col = entry.key ~/ 100;
    final row = entry.key % 100;
    final group = entry.value..sort(ResolvedSession.compare);
    for (var i = 0; i < group.length; i++) {
      final s = group[i];
      out.add(
        PlacedSession(
          session: s,
          col: col,
          row: row,
          span: s.startPeriod == null || s.endPeriod == null
              ? 1
              : rowsSpanned(s.startPeriod!, s.endPeriod!),
          lane: i,
          lanes: group.length,
        ),
      );
    }
  }
  return out;
}

/// 网格上还空着、可以「点一下新增」的格子。
///
/// 「被占」要按**跨越的行**算：1-4 节的连堂课占了两行，只看起始行的话，
/// 它下面那一行会显示成可选，点上去就叠出了第二门课。
///
/// 停课的幽灵块也算被占 —— 那里本来就有一门课，再叠一门只会让人困惑。
/// 要动那一格，先点开幽灵块处理掉它。
///
/// 抽成纯函数是为了能直接断言，不必靠截图去数格子。
List<({int weekday, int row, int startPeriod})> freeSlots(
  List<PlacedSession> placed,
) {
  final taken = <int>{};
  for (final p in placed) {
    for (var i = 0; i < p.span; i++) {
      taken.add((p.col + 1) * 100 + p.row + i);
    }
  }

  return [
    for (var row = 0; row < kPeriodRowCount; row++)
      for (var col = 0; col < 7; col++)
        if (!taken.contains((col + 1) * 100 + row))
          (
            weekday: col + 1,
            row: row,
            startPeriod: kPeriodSlots[row].startPeriod,
          ),
  ];
}

class _Header extends StatelessWidget {
  const _Header({
    required this.week,
    required this.week1Monday,
    required this.cellWidth,
    required this.now,
  });

  final int week;
  final DateTime week1Monday;
  final double cellWidth;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final monday = weekMondayOf(week1Monday, week);
    final today = now == null ? null : dateOnly(now!);
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: _gutterWidth,
          child: Center(
            child: Text(
              '第$week周',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
        ),
        for (var i = 0; i < 7; i++)
          SizedBox(
            width: cellWidth,
            child: Builder(
              builder: (context) {
                final date = monday.add(Duration(days: i));
                final isToday = today != null && isSameDay(date, today);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _weekdayNames[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: isToday
                          ? BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(
                        '${date.month}/${date.day}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isToday ? scheme.onPrimary : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.gutterWidth,
    required this.cellWidth,
    required this.rowHeight,
    required this.rows,
    required this.color,
  });

  final double gutterWidth;
  final double cellWidth;
  final double rowHeight;
  final int rows;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    for (var r = 1; r < rows; r++) {
      final y = r * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (var c = 0; c <= 7; c++) {
      final x = gutterWidth + c * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cellWidth != cellWidth ||
      old.rowHeight != rowHeight ||
      old.rows != rows ||
      old.gutterWidth != gutterWidth;
}

/// 单个大节的标签：节次号 + 起止时间。
class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({required this.rowIndex});

  final int rowIndex;

  @override
  Widget build(BuildContext context) {
    final slot = kPeriodSlots[rowIndex];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${slot.startPeriod}-${slot.endPeriod}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          formatMinutes(slot.startMinute),
          style: TextStyle(fontSize: 9, color: scheme.outline),
        ),
        Text(
          formatMinutes(slot.endMinute),
          style: TextStyle(fontSize: 9, color: scheme.outline),
        ),
      ],
    );
  }
}
