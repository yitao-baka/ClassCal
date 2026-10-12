/// 设置页 —— 外观、主题色、课前提醒、桌面小组件。
///
/// 这一页是**入口的集合**：每一项都只放一行摘要，点进去才是完整的设置。
/// 摘要不是为了好看，而是为了让人不用点进去就知道现在是什么状态 ——
/// 提醒「以为开着其实关着」的代价是一节课，小组件「配了半天没放上桌面」
/// 的代价是白折腾一遍。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/native_sync.dart';
import '../../app/providers.dart';
import '../../app/settings_providers.dart';
import '../../core/platform/home_widget.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/course_colors.dart';
import 'abbr_page.dart';
import 'reminder_page.dart';
import 'reminder_scope.dart';
import 'tabs_page.dart';
import 'widget_page.dart';

void showSettingsPage(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _section(context, '外观'),
          RadioGroup<AppThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (v) => v == null
                ? null
                : notifier.update((s) => s.copyWith(themeMode: v)),
            child: const Column(
              children: [
                RadioListTile<AppThemeMode>(
                  value: AppThemeMode.system,
                  title: Text('跟随系统'),
                ),
                RadioListTile<AppThemeMode>(
                  value: AppThemeMode.light,
                  title: Text('浅色'),
                ),
                RadioListTile<AppThemeMode>(
                  value: AppThemeMode.dark,
                  title: Text('深色'),
                ),
              ],
            ),
          ),
          const Divider(),
          _section(context, '主题色'),
          _ColorSourceTile(settings: settings, notifier: notifier),
          const _WallpaperNote(),
          const Divider(),
          _section(context, '课程颜色'),
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('默认按课程名自动配色'),
            subtitle: Text(
              '同一门课在网格上永远是同一个颜色；单独改某一门，'
              '打开那节课的「编辑课程」即可。',
            ),
          ),
          const Divider(),
          _section(context, '课程缩写'),
          _AbbrEntry(settings: settings),
          const Divider(),
          _section(context, '标签页'),
          const _TabsEntry(),
          const Divider(),
          _section(context, '课前提醒'),
          _ReminderEntry(settings: settings),
          const Divider(),
          _section(context, '桌面小组件'),
          const _WidgetEntry(),
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
}

/// 提醒入口。
///
/// 摘要里带上「提前 15 分钟」和「已关」这类信息，是为了让用户不用点进去
/// 就知道现在是什么状态 —— 提醒这种东西「以为开着其实关着」的代价是一节课。
class _ReminderEntry extends ConsumerWidget {
  const _ReminderEntry({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(reminderCapabilitiesProvider).value;
    final scheme = Theme.of(context).colorScheme;

    // 通知被关掉时在这里就说 —— 这是用户最可能在别处（系统设置、清理软件）
    // 无意中关掉、又最想不到的一项。
    final blocked =
        settings.remindersEnabled &&
        caps != null &&
        caps.supported &&
        !caps.notificationsGranted;

    return ListTile(
      leading: const Icon(Icons.alarm),
      title: const Text('课前提醒'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // 摘要格式和日程页共用一份（`reminderSummary`）—— 分开写的话，
            // 同一套设置会长出两种说法，而用户是靠「数字对不对得上」来判断
            // 改没改成功的。
            settings.remindersEnabled
                ? reminderSummary(SetReminderSettings.fromGlobal(settings))
                : '已关闭',
          ),
          // 通知开着但横幅关掉时，这一页是用户唯一会看到提示的地方 ——
          // 他大概率永远不进提醒页，只会在某天发现「提醒怎么不弹」。
          if (settings.remindersEnabled && caps != null && caps.banners == false && caps.notificationsGranted)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '通知不会以横幅弹出，只进通知栏',
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '通知权限被关掉了，现在弹不出来',
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showReminderPage(context),
    );
  }
}

/// 小组件入口。
///
/// 摘要只看**放没放**：这一块没有全局开关（每个实例各自选显示什么），
/// 所以能给的最有用的信息就是「桌面上有没有、放了几个」—— 用户最容易困惑的
/// 也正是「我配了半天，桌面上怎么没有」。
class _WidgetEntry extends ConsumerWidget {
  const _WidgetEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(homeWidgetStatusProvider).value;

    return ListTile(
      leading: const Icon(Icons.widgets_outlined),
      title: const Text('桌面小组件'),
      subtitle: Text(
        switch (status) {
          null => '正在读取…',
          HomeWidgetStatus(supported: false) => '当前平台不支持（Windows 端在后面的阶段做）',
          HomeWidgetStatus(count: 0) =>
            '还没有放置。长按桌面 → 小组件，找「ClassCal」',
          HomeWidgetStatus(count: final n, hasSnapshot: true) => '桌面上放了 $n 个',
          HomeWidgetStatus(count: final n) => '桌面上放了 $n 个，但还没同步过课表',
        },
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showWidgetPage(context),
    );
  }
}

/// 标签页入口。
///
/// 摘要说清「有几个日程」和「打开时停在哪」：顺序和默认页都是**改完看不出来**
/// 的东西 —— 得杀进程重开一次才知道生效没有，所以至少让这一行先把现状说清。
class _TabsEntry extends ConsumerWidget {
  const _TabsEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(tabEntriesProvider);
    final settings = ref.watch(settingsProvider);

    return ListTile(
      leading: const Icon(Icons.tab),
      title: const Text('标签页'),
      subtitle: Text(tabsSummary(entries: entries, settings: settings)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showTabsPage(context),
    );
  }
}

/// 课程缩写入口。
///
/// 摘要说清「改了几个」和「看起来像什么」：这一项的效果在桌面上，不在 App 里，
/// 只说「课程缩写」四个字的话，用户点进去才发现是给小组件用的。
class _AbbrEntry extends ConsumerWidget {
  const _AbbrEntry({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = settings.courseAbbrs.length;

    return ListTile(
      leading: const Icon(Icons.text_fields),
      title: const Text('课程缩写'),
      subtitle: Text(
        count == 0
            ? '桌面小组件的周网格里用缩写，已有预设；点进去可以逐门改'
            : '已自定义 $count 门课，其余用预设',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showAbbrPage(context),
    );
  }
}

class _ColorSourceTile extends StatelessWidget {
  const _ColorSourceTile({required this.settings, required this.notifier});

  final AppSettings settings;
  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<AppColorSource>(
      groupValue: settings.colorSource,
      onChanged: (v) =>
          v == null ? null : notifier.update((s) => s.copyWith(colorSource: v)),
      child: Column(
        children: [
          const RadioListTile<AppColorSource>(
            value: AppColorSource.wallpaper,
            title: Text('跟随壁纸'),
            subtitle: Text('取系统按壁纸算好的主题色，换壁纸自动跟着变'),
          ),
          RadioListTile<AppColorSource>(
            value: AppColorSource.custom,
            title: const Text('自定颜色'),
            subtitle: Text(
              settings.customSeedHex,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (settings.colorSource == AppColorSource.custom)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: HexColorField(
                hex: settings.customSeedHex,
                onChanged: (hex) =>
                    notifier.update((s) => s.copyWith(customSeedHex: hex)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 壁纸取色在低版本上没有 —— 说清楚原因，而不是给一个点不动的选项让人猜。
class _WallpaperNote extends ConsumerWidget {
  const _WallpaperNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(wallpaperAccentProvider);
    final scheme = Theme.of(context).colorScheme;

    final text = switch (palette) {
      AsyncData(value: null) =>
        '当前设备没给出壁纸主题色（需要 Android 12 及以上）。'
            '已经退回预设颜色，可以直接在下面选一个自定色。',
      AsyncLoading() => '正在读取壁纸主题色…',
      AsyncError() => '读取壁纸主题色失败，已退回预设颜色。',
      _ => '已从系统读到壁纸主题色。',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: scheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// 十六进制颜色输入 —— 一行输入框加一排常用色。
///
/// 没上取色器控件是权衡过的：`flex_color_picker` 4.x 已经迁到 `material_ui`
/// 包，而我们刻意留在 in-framework 的 Material 上；为一个颜色选择引入版本
/// 风险不划算。手输 hex 能表达的颜色比任何取色器都全，预设色则覆盖了
/// 「随手挑一个好看的颜色」这个高频场景。
class HexColorField extends StatefulWidget {
  const HexColorField({super.key, required this.hex, required this.onChanged});

  final String hex;
  final ValueChanged<String> onChanged;

  @override
  State<HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<HexColorField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.hex,
  );
  String? _error;

  /// 输入过程中的中间态（比如刚敲了 `#`）不该算错，只有「已经不可能变对」
  /// 才提示。判据：长度够了却仍然解析不出来。
  void _onChanged(String raw) {
    final s = raw.trim();
    final complete = s.replaceFirst('#', '').length >= 6;
    final parsed = parseHexColor(s);
    setState(() {
      _error = (complete && parsed == null) ? '需要 #RRGGBB 格式' : null;
    });
    if (parsed != null) widget.onChanged(toHexColor(parsed));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = parseHexColor(widget.hex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: '十六进制颜色',
            hintText: '#6750A4',
            isDense: true,
            errorText: _error,
            prefixIcon: Padding(
              padding: const EdgeInsets.all(10),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color:
                      current ??
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in kSeedSwatches)
              _Swatch(
                color: c,
                selected: current == c,
                onTap: () {
                  final hex = toHexColor(c);
                  _controller.text = hex;
                  setState(() => _error = null);
                  widget.onChanged(hex);
                },
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
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: selected
            ? Border.all(
                color: Theme.of(context).colorScheme.onSurface,
                width: 2.5,
              )
            : null,
      ),
      child: selected
          ? Icon(Icons.check, size: 16, color: onCourseColor(color))
          : null,
    ),
  );
}
