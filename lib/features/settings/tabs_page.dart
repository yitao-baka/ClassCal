/// 标签页设置 —— 总览开关、顺序、打开时停在哪一页。
///
/// 这三件事放一页，因为它们回答的是同一个问题：「这几页怎么摆」。
///
/// **顺序存在设置文件里，不在数据库里。** 直接的道理是 `CalendarSets` 那张表
/// 一行一个整数，表达不了「总览插在第二和第三个日程之间」—— 总览没有 id，
/// 也就没有那一列。但拖完仍然会**顺手把名次写回**那一列（见
/// `CalendarRepository.writeTabOrder`）：导出 JSON 备份时带的是那一列，而设置
/// 文件不会跟着备份走，不写回的话「备份看起来有顺序、恢复出来却是乱的」。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/settings_providers.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/schedule_ref.dart';
import '../../core/theme/course_colors.dart';

void showTabsPage(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TabsPage()),
    );

/// 设置页那一行摘要。
///
/// 摘要里必须带上「打开时停在哪个日程」：这一项设错了，用户每天要经过一次
/// 才能发现，而那时他多半只会觉得「怎么老停在这一页」。
String tabsSummary({
  required List<TabEntry> entries,
  required AppSettings settings,
}) {
  final sets = entries.where((e) => !e.isOverview).length;
  if (sets == 0) return '还没有日程';

  final landing = entries.where((e) => e.key == settings.defaultTab).firstOrNull ??
      // `''`（第一个日程）、以及指向已删日程的坏值，都落在这一级上。
      // 和 `effectiveTabProvider` 的回退是同一个意思 —— 摘要说的是**实际会停的
      // 那一页**，不是设置里那个字符串。
      entries.firstOrNull;
  final name = landing?.name;
  return '$sets 个日程 · 打开时停在「${name ?? '—'}」';
}

class TabsPage extends ConsumerWidget {
  const TabsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final entries = ref.watch(tabEntriesProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('标签页')),
      body: ReorderableListView(
        // 顺序列表和后面的「默认显示」一起滚，所以用 header / footer 而不是
        // 把它塞进外层 ListView —— 后者要么把拖拽区域压成固定高度，
        // 要么就得套两层滚动。
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              value: settings.overviewEnabled,
              title: const Text('显示「总览」'),
              subtitle: const Text(
                '把全部日程的事件合在一张周网格上看。'
                '它没有自己的日程，也就没有自己的提醒设置 —— 提醒跟着事件所属的日程走。\n'
                '只有一个日程时不显示这一页：那会是一个和它一模一样的页。',
              ),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(overviewEnabled: v)),
            ),
            const Divider(),
            _section(context, '顺序'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                entries.length < 2
                    ? '只有一个日程，还排不出顺序。再导入一份就会出现在这里。'
                    : '按住右边的拖柄上下拖。这个顺序也会写进导出的 JSON 备份。',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(),
            _section(context, '打开时停在'),
            _DefaultTabPicker(settings: settings, entries: entries),
            const SizedBox(height: 24),
          ],
        ),
        // 自己画拖柄：默认那套在手机上要长按整行，而这一行本身没有别的动作，
        // 长按这一下没有任何提示，用起来像「拖不动」。
        buildDefaultDragHandles: false,
        // 用 `onReorderItem` 而不是老的 `onReorder`：新回调的 `newIndex`
        // **已经**替调用方减掉了「自己占的那一格」，不必再写一次
        // `if (to > from) to -= 1` —— 那一行是这类代码最常见的差一错误。
        onReorderItem: (from, to) => _reorder(ref, entries, from, to),
        children: [
          for (var i = 0; i < entries.length; i++)
            _OrderRow(
              key: ValueKey(entries[i].key),
              index: i,
              entry: entries[i],
            ),
        ],
      ),
    );
  }

  static Widget _section(BuildContext context, String text) => Padding(
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

  /// 拖完一次：把整个顺序写进设置，并**顺手写回数据库那一列**。
  ///
  /// 写的是**整个列表**而不是「谁挪到了哪」：`tabOrder` 的语义本来就是一张
  /// 完整的名次表，只交出变化的那一项会让「没列出来的接在后面」这条规则
  /// 到处漏风。
  ///
  /// [to] 是**已经把被拖走那一格排除掉之后**的目标下标（`onReorderItem`
  /// 的约定），所以这里直接 `insert`，不需要再减一。
  static void _reorder(
    WidgetRef ref,
    List<TabEntry> entries,
    int from,
    int to,
  ) {
    final keys = [for (final e in entries) e.key];
    if (from < 0 || from >= keys.length) return;
    // 先摘掉再判 [to]：摘掉之后列表短了一格，合法下标是 `0..length`（含末尾）。
    final moved = keys.removeAt(from);
    if (to < 0 || to > keys.length) return;
    keys.insert(to, moved);

    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(tabOrder: keys));
    // 落库是次要目的（给导出的备份用），失败了也只是备份里那一列陈旧 ——
    // 不值得为它拦住界面，也不该在这里弹错误框。
    unawaited(ref.read(repositoryProvider).writeTabOrder(keys));
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({super.key, required this.index, required this.entry});

  final int index;
  final TabEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        radius: 8,
        backgroundColor: entry.isOverview
            ? scheme.outline
            : parseHexColor(entry.colorSeedHex) ?? scheme.primary,
      ),
      title: Text(entry.name),
      subtitle: entry.isOverview
          ? const Text('全部日程合起来看')
          : Text(ScheduleRef.ofSet(entry.setId!)),
      trailing: ReorderableDragStartListener(
        index: index,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.drag_handle),
        ),
      ),
    );
  }
}

/// 「打开时停在」那一组。
///
/// 第一个日程和「固定某个日程」是**两个不同的选项**，哪怕它们现在指向同一页：
/// 前者跟着顺序走（顺序一改它也跟着变），后者钉死在那个 id 上。合并成一个会
/// 让「我把顺序调了，怎么打开还是那一页」变成没法表达的困惑。
class _DefaultTabPicker extends ConsumerWidget {
  const _DefaultTabPicker({required this.settings, required this.entries});

  final AppSettings settings;
  final List<TabEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = entries.firstOrNull;
    return RadioGroup<String>(
      groupValue: settings.defaultTab,
      onChanged: (v) => v == null
          ? null
          : ref
              .read(settingsProvider.notifier)
              .update((s) => s.copyWith(defaultTab: v)),
      child: Column(
        children: [
          RadioListTile<String>(
            value: ScheduleRef.unset,
            title: const Text('第一个日程'),
            subtitle: Text(
              first == null ? '还没有日程' : '现在是「${first.name}」，跟着顺序走',
            ),
          ),
          for (final e in entries)
            RadioListTile<String>(
              value: e.key,
              title: Text(e.name),
              subtitle: Text(
                e.isOverview ? '合并显示，没有自己的周号' : ScheduleRef.ofSet(e.setId!),
              ),
            ),
        ],
      ),
    );
  }
}
