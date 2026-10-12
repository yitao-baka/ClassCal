/// 课程缩写的编辑页。
///
/// 缩写只出现在桌面小组件的**周网格**格子里 —— 一列只有屏宽的七分之一，
/// 写全称的结果是每格都被截成「高等数…」。默认已经预置了一套校内叫法
/// （`高数` / `离散` / `大英`），这一页是给「预置的那套不合我的习惯」用的。
///
/// 这一页只改**用户覆盖表**（`AppSettings.courseAbbrs`），改完 `NativeSync`
/// 那条链子会自己把新快照推下去，桌面上的格子跟着变。这里不碰预置表 ——
/// 清空输入框就是「用回预置的」，不需要另一个按钮。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/settings_providers.dart';
import '../../core/text/course_abbr.dart';

void showAbbrPage(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AbbrPage()),
    );

/// 全部课表里出现过的课程标题，去重后按字典序排。
///
/// 取的是**模板 + 单次事件**的标题，而不是「这一周解析出来的那些课」：
/// 一门只在第 12 周上的课，在第 5 周打开这一页时也该能改缩写 ——
/// 按当周去列，用户会遇到「这门课怎么不在这儿」。
final courseTitlesProvider = Provider<List<String>>((ref) {
  final sets = ref.watch(allSetsDataProvider).value ?? const [];
  return distinctCourseTitles([
    for (final s in sets) ...s.templates.map((t) => t.title),
    for (final s in sets) ...s.oneOffs.map((e) => e.title),
  ]);
});

class AbbrPage extends ConsumerStatefulWidget {
  const AbbrPage({super.key});

  @override
  ConsumerState<AbbrPage> createState() => _AbbrPageState();
}

class _AbbrPageState extends ConsumerState<AbbrPage> {
  /// 每个标题一个控制器，**存在 State 里而不是 build 里现建** ——
  /// 每次 build 都新建一个的话，输入一个字符光标就跳回开头。
  final _controllers = <String, TextEditingController>{};

  TextEditingController _controllerFor(String title, String current) =>
      _controllers.putIfAbsent(title, () => TextEditingController(text: current));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titles = ref.watch(courseTitlesProvider);
    final settings = ref.watch(settingsProvider);
    final overrides = settings.courseAbbrs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程缩写'),
        actions: [
          if (overrides.isNotEmpty)
            TextButton(
              onPressed: () => _resetAll(titles),
              child: const Text('全部恢复预置'),
            ),
        ],
      ),
      body: titles.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('还没有日程。导入之后这里会列出每一门课。'),
            )
          : ListView.builder(
              // 用 `.builder` 而不是 `ListView(children: [...])`：列表字面量
              // 会在**建页时**就对每一门课跑一遍 `_controllerFor` 和 `_AbbrRow`
              // （每行一个输入框、每行还要算一次预设缩写），而课程数是用户数据
              // —— 这一页是全 App 唯一一条会随数据长起来的列表。
              //
              // 前两行是说明和分隔线、最后一行是收尾留白，所以 `itemCount`
              // 比课数多 3，索引整体偏移 2。
              itemCount: titles.length + 3,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      '缩写只用在桌面小组件的周网格里 —— 一格放不下三个字。'
                      '留空就用预设的那个（灰色显示在框里）。',
                    ),
                  );
                }
                if (i == 1) return const Divider();
                if (i == titles.length + 2) return const SizedBox(height: 24);
                final title = titles[i - 2];
                return _AbbrRow(
                  key: ValueKey(title),
                  title: title,
                  controller: _controllerFor(title, overrides[title] ?? ''),
                  onChanged: (v) => _setAbbr(title, v),
                );
              },
            ),
    );
  }

  void _setAbbr(String title, String value) {
    final next = Map<String, String>.from(ref.read(settingsProvider).courseAbbrs);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      // 留着这个空条目而不是删掉：它和「没配过」在 `abbrFor` 里是同一个意思
      // （空值回落到预置），但留着能让这一页知道用户**动过**这一行。
      next[title] = '';
    } else {
      next[title] = clampAbbr(trimmed);
    }
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(courseAbbrs: next));
  }

  void _resetAll(List<String> titles) {
    for (final t in titles) {
      _controllers[t]?.clear();
    }
    ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(courseAbbrs: const {}),
        );
  }
}

class _AbbrRow extends StatelessWidget {
  const _AbbrRow({
    super.key,
    required this.title,
    required this.controller,
    required this.onChanged,
  });

  final String title;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final preset = presetAbbrFor(title);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '预设：$preset',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              maxLength: kMaxAbbrChars,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                // 提示语就是预置值：空框里显示的字，正是留空之后会用的那个。
                // 比在下面写一行「留空则使用 高数」更直接 —— 用户看到的
                // 就是结果本身。
                hintText: preset,
                isDense: true,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
