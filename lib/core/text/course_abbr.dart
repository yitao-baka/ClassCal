/// 课程缩写。
///
/// 桌面小组件的**周网格**是一张缩略图：一列只有屏宽的七分之一，格子里放下
/// 三个汉字已经是极限。写全称的结果是每格都被截成「高等数…」，读起来比不写
/// 还费劲；而只给一个色块，人又得靠颜色去猜 —— 十二门课十二条颜色，
/// 认得出的没有几门。
///
/// 所以网格里画**缩写**。缩写按用户手动指定的优先，其次是这里预置的一套常见
/// 叫法（`高数` / `离散` / `大英`，校内本来就是这么叫的），两者都没有才退回
/// 一条规则去猜。
///
/// 这一条和 `course_colors.dart` 是同一个位置上的东西，所以放在同一层：
/// **它必须只存在一份**。原生侧只拿到算好的字符串，不参与命名 ——
/// 在 Kotlin 里再写一遍这套规则，两边迟早走偏，表现是「同一门课在 App 里
/// 叫『高数』、桌面上叫『高等』」，而没有任何东西会报错。
library;

/// 缩写的长度上限。
///
/// 不是给渲染用的限制（渲染那侧会自己缩字号、必要时折行），是给**输入**用的：
/// 一个 12 字的「缩写」能把格子撑爆，而那是手滑，不是本意。
const int kMaxAbbrChars = 6;

/// 没配出缩写时用的兜底。
const String kFallbackAbbr = '课程';

/// 预置缩写表：`(关键词, 缩写)`，按**顺序**匹配，命中第一个就返回。
///
/// 用关键词子串而不是完整课名，是因为课名后面总挂着 `(1)`、`A`、`（必修）`
/// 这类后缀，而且同一门课在不同学期叫法也会微调。子串能一起吃下这些变体。
///
/// **顺序有意义**：更具体的必须排在更笼统的前面（`大学外语` 要排在 `外语`
/// 之前，`程序设计实验` 要排在 `程序设计` 之前），否则笼统的那条先命中，
/// 具体的那门课就永远拿不到自己的缩写。
const List<(String, String)> kAbbrPresets = <(String, String)>[
  // 数学 / 物理 / 化学这类公共基础课，各校叫法基本固定
  ('高等数学', '高数'),
  ('离散数学', '离散'),
  ('线性代数', '线代'),
  ('概率论', '概率'),
  ('数理统计', '统计'),
  ('复变函数', '复变'),
  ('大学物理', '大物'),
  ('大学化学', '大化'),

  // 外语 / 体育 / 语文
  ('大学英语', '大英'),
  ('大学外语', '大英'),
  ('专业英语', '专英'),
  ('大学体育', '体育'),
  ('大学语文', '大语'),

  // 思想政治系列
  ('思想道德与法治', '思修'),
  ('思想道德修养', '思修'),
  ('中国近现代史', '近代史'),
  ('马克思主义', '马原'),
  ('毛泽东思想和', '毛概'),
  ('形势与政策', '形策'),
  ('军事理论', '军事'),
  ('军事技能', '军训'),
  ('国家安全', '国安'),

  // 计算机类
  ('数据结构', '数构'),
  ('操作系统', '操统'),
  ('计算机网络', '计网'),
  ('数据库', '数据库'),
  ('编译原理', '编译'),
  ('软件工程', '软工'),
  ('物联网', '物联网'),

  // 这四条**顺序不能动**（见上面那条「顺序有意义」）：
  // `C语言程序设计实验` 同时含有下面每一条关键词，排在前面的先命中，
  // 所以必须从最长的开始。少了第一行，那门实验课会拿到一个光秃秃的
  // `实验` —— 和另外几门实验课撞成一样。
  ('C语言程序设计实验', 'C实验'),
  ('C语言程序设计', 'C语言'),
  ('程序设计实验', '实验'),
  ('程序设计', '程设'),

  // 心理 / 通识
  ('心理健康', '心理'),
  ('创新创业', '双创'),
  ('职业生涯', '职规'),
];

/// 结尾的「废话」，猜缩写时先剥掉。
///
/// `物联网工程导论` 剥完是 `物联网工程`，再取前三个字正好是 `物联网`；
/// `数据库原理` 剥完是 `数据库`。不剥的话取前三个字会得到 `物联网`（碰巧对）
/// 和 `数据库`（也对），但 `大学物理实验` 会变成 `大学物`。
///
/// **从长到短排**，否则 `与实践` 会被 `实践` 先吃掉一半。
const List<String> _kNoiseSuffixes = <String>[
  '与指导',
  '与实践',
  '与技术',
  '导论',
  '概论',
  '教程',
  '基础',
  '理论',
  '原理',
  '实验',
  '实践',
];

/// 猜缩写时取几个字。
///
/// 3 而不是 4：格子只放得下三个，取四个的结果是每个格子都得缩号折行，
/// 而第四个字多半是「学」「课」「论」这种没有信息量的。
const int _kGuessChars = 3;

/// 结尾的括号后缀（`(1)` / `（二）` / `[必修]`）。
///
/// 提到文件级是因为它原来是每次调用现 new 一个 —— 而 `presetAbbrFor` 是
/// **每门课一行**都会调的（课程缩写页），课程数是用户数据（几十门很正常），
/// 于是同一个正则被反复编译几十遍。`RegExp` 没有 `const` 构造，只能放这里。
final RegExp _kParenSuffix = RegExp(r'[\(\[（【][^\)\]）】]*[\)\]）】]\s*$');

/// 去掉 `(1)` / `（二）` / `[必修]` 这类括号后缀。
///
/// 只削**结尾**的：`C语言程序设计（实验）` 这种把关键信息放在括号里的写法，
/// 削掉之后反而更干净，但 `大学生心理健康教育与指导` 中间没有括号，
/// 一刀切地削中间会把 `A(1)` 的 `A` 也带走 —— 那个 `A` 区分高数 A/B，有用。
String _stripParenSuffix(String s) {
  var out = s.trim();
  // 循环削：`大学英语(1)(必修)` 这种连着挂两层的不是没有。
  while (true) {
    final m = _kParenSuffix.firstMatch(out);
    if (m == null) break;
    out = out.substring(0, m.start).trim();
  }
  return out;
}

/// 规则猜出来的缩写（**不考虑用户覆盖**）。
///
/// 预置表在前、规则在后。规则按顺序做三件事：削括号后缀 → 剝结尾废话 →
/// 取前三个字。每一步都会让名字更短，但也更容易认不出 —— 所以它只是兜底，
/// 真正的答案是用户在设置里自己写一个。
String presetAbbrFor(String title) {
  final name = title.trim();
  if (name.isEmpty) return kFallbackAbbr;

  for (final (keyword, abbr) in kAbbrPresets) {
    if (name.contains(keyword)) return abbr;
  }

  var guess = _stripParenSuffix(name);
  for (final suffix in _kNoiseSuffixes) {
    if (guess.length > suffix.length && guess.endsWith(suffix)) {
      guess = guess.substring(0, guess.length - suffix.length);
      break;
    }
  }
  if (guess.isEmpty) guess = name;

  // 剥完只剩一两个字就拿它本身 —— 再取前三个字也不会更短了。
  return guess.length <= _kGuessChars
      ? guess
      : guess.substring(0, _kGuessChars);
}

/// 这门课最终显示在格子里的缩写。
///
/// 优先级刻意和 `courseColor` 一样：**用户写的 → 预置的**。
/// [overrides] 的键是课程标题，和 `courseColor` 按标题取色是同一个约定 ——
/// 同一门课拆成星期一、星期五两条模板时，它们共用同一个缩写。
///
/// 空白字符串的覆盖当作「没写」：设置页里清空输入框的意思就是「用回预置的」，
/// 而不是「显示成空」。
String abbrFor(String title, {Map<String, String> overrides = const {}}) {
  final key = title.trim();
  var custom = overrides[key];
  if (custom == null) {
    // 覆盖表的键也可能前后带空格 —— 它是从设置里那份 JSON 读回来的，
    // 手改过或者从旧备份导入过的文件都可能有。直接查不到时再扫一遍，
    // 漏掉这一手的结果是「用户明明配了缩写，桌面上还是预置的那个」。
    // 表只有几十条，不值得为它常驻一份规范化副本。
    for (final e in overrides.entries) {
      if (e.key.trim() == key) {
        custom = e.value;
        break;
      }
    }
  }

  final written = custom?.trim();
  if (written != null && written.isNotEmpty) return clampAbbr(written);
  return clampAbbr(presetAbbrFor(key));
}

/// 把 [s] 收进 [kMaxAbbrChars] 之内。
///
/// 用户输入那一侧已经限制了长度，这里是**第二道**：覆盖表是从磁盘读回来的
/// （也可能是从旧备份导入的），一份手改过的 JSON 能塞进任意长的一个字符串，
/// 而它最后会变成位图里的一行字 —— 长了不会报错，只会把格子撑破。
String clampAbbr(String s) {
  final trimmed = s.trim();
  if (trimmed.length <= kMaxAbbrChars) return trimmed;
  return trimmed.substring(0, kMaxAbbrChars);
}

/// 某一套课表里出现过的全部课程标题，去重后按字典序排。
///
/// 设置页拿它列清单。用**标题**而不是模板 id 当键，和 [abbrFor] 一致：
/// 同一门课的两条模板只该出现一次。
List<String> distinctCourseTitles(Iterable<String> titles) {
  final seen = <String>{};
  for (final t in titles) {
    final name = t.trim();
    if (name.isNotEmpty) seen.add(name);
  }
  return seen.toList()..sort();
}
