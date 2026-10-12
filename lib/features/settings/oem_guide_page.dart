/// 厂商后台限制的引导页。
///
/// 这一页存在的理由很直接：**国产 ROM 的电池优化会拦掉后台闹钟**，
/// 而这是唯一一个「我们没有 bug、用户也没做错，功能就是不工作」的场景。
/// 不给引导的话，用户看到的表现是「提醒偶尔不响」—— 一个查不出原因的间歇性
/// 故障，最后只能归结为「这 App 不好用」。
///
/// 内容参考 dontkillmyapp.com 的分级数据。ROM 的菜单路径会随版本改，
/// 所以每一段都写成「找这几个词」，而不是「第 3 个菜单第 2 项」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/native_sync.dart';

void showOemGuidePage(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OemGuidePage()),
    );

/// 一个厂商的引导。
class _Brand {
  const _Brand({
    required this.keys,
    required this.name,
    required this.steps,
  });

  /// 用来和 `Build.MANUFACTURER` 对上的关键词（小写）。
  final List<String> keys;
  final String name;
  final List<String> steps;
}

const List<_Brand> _brands = [
  _Brand(
    keys: ['xiaomi', 'redmi', 'poco'],
    name: '小米 / 红米（MIUI、HyperOS）',
    steps: [
      '设置 → 应用设置 → 应用管理 → ClassCal',
      '打开「自启动」',
      '「省电策略」改成「无限制」',
      '「权限管理 → 后台弹出界面」允许（不然通知弹不出来）',
      '锁屏清理里把 ClassCal 加进白名单',
    ],
  ),
  _Brand(
    keys: ['huawei'],
    name: '华为（EMUI、HarmonyOS）',
    steps: [
      '设置 → 应用 → 应用启动管理 → ClassCal',
      '关掉「自动管理」，会露出下面三个开关',
      '手动打开「自启动」「关联启动」「后台活动」',
      '设置 → 电池 → 更多电池设置 → 关掉「休眠时始终保持网络连接」之外的省电项',
    ],
  ),
  _Brand(
    keys: ['honor'],
    name: '荣耀（MagicOS）',
    steps: [
      '设置 → 应用 → 应用启动管理 → ClassCal',
      '关掉「自动管理」，手动打开「自启动」「关联启动」「后台活动」',
    ],
  ),
  _Brand(
    keys: ['oppo', 'oneplus', 'realme', 'oplus'],
    name: 'OPPO / 一加 / realme（ColorOS）',
    steps: [
      '设置 → 电池 → 应用耗电管理 → ClassCal',
      '允许「后台运行」「自启动」「关联启动」',
      '设置 → 电池 → 更多设置 → 关掉「智能省电」对 ClassCal 的限制',
    ],
  ),
  _Brand(
    keys: ['vivo', 'iqoo'],
    name: 'vivo / iQOO（OriginOS、Funtouch）',
    steps: [
      '设置 → 电池 → 后台高耗电 → 允许 ClassCal',
      'i 管家 → 应用管理 → 权限管理 → 自启动 → 允许 ClassCal',
      '设置 → 更多设置 → 权限管理 → ClassCal → 后台弹窗 → 允许',
    ],
  ),
  _Brand(
    keys: ['samsung'],
    name: '三星（One UI）',
    steps: [
      '设置 → 电池和设备维护 → 电池 → 后台使用限制',
      '把 ClassCal 从「休眠应用」里去掉，并加进「从不休眠的应用」',
    ],
  ),
  _Brand(
    keys: ['meizu'],
    name: '魅族（Flyme）',
    steps: [
      '手机管家 → 权限管理 → 后台管理 → ClassCal → 允许后台运行',
    ],
  ),
];

class OemGuidePage extends ConsumerWidget {
  const OemGuidePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(reminderCapabilitiesProvider).value;
    final manufacturer = (caps?.manufacturer ?? '').toLowerCase();
    final scheme = Theme.of(context).colorScheme;

    // 本机厂商排在最前面 —— 用户点进这一页就是为了解决自己手机上那个问题，
    // 让他从七个品牌里找自己那个是没必要的。
    final mine = _brands
        .where((b) => b.keys.any((k) => manufacturer.contains(k)))
        .toList();
    final others = _brands.where((b) => !mine.contains(b)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('后台限制')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '提醒是靠系统闹钟触发的，不需要 App 一直开着 —— 但厂商的省电策略'
              '会把后台闹钟一起掐掉。把它加进白名单之后，提醒才会稳定。',
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('直接打开自启动设置'),
                onPressed: () async {
                  await ref.read(reminderSchedulerProvider).openAutoStartSettings();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('如果跳到了应用详情页，请在里面找「自启动」或「电池」')),
                  );
                },
              ),
            ),
          ),
          // 这个按钮是「尽力而为」的：各家 ROM 的页面类名都不公开、随版本改，
          // 跳不过去是常态。所以下面永远把手工路径写全，那个才是保底。
          for (final brand in mine) _BrandCard(brand: brand, isMine: true),
          for (final brand in others) _BrandCard(brand: brand, isMine: false),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Text(
              '另外：开启「省电模式」「超级省电」会一律拦掉后台闹钟，'
              '上课那天最好别开。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.brand, required this.isMine});

  final _Brand brand;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: isMine ? scheme.secondaryContainer : null,
      child: ExpansionTile(
        // 认出来的那个默认展开；其余的折起来，免得七个品牌铺满一屏。
        initiallyExpanded: isMine,
        title: Row(
          children: [
            Flexible(child: Text(brand.name)),
            if (isMine) ...[
              const SizedBox(width: 8),
              // 用 text 而不是 Chip：Chip 有固定的最小高度，塞进
              // ListTile 的标题行会把行高撑开，和别的卡片对不齐。
              Text(
                '本机',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ],
        ),
        children: [
          for (final step in brand.steps)
            ListTile(
              dense: true,
              leading: const Icon(Icons.chevron_right, size: 18),
              title: Text(step, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
