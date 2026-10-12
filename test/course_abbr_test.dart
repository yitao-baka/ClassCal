import 'package:classcal/core/text/course_abbr.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课程缩写。
///
/// 这一层错了**桌面上看不出来**：格子里写着「高等」而不是「高数」，看起来
/// 只是缩写起得不好，没人会去查是代码错了还是预置表没覆盖到。所以这里把
/// **真实课表的 12 门课逐条钉死** —— 预置表改了、或者关键词顺序动了，
/// 哪一门课掉出预置、掉到规则兜底上去，这里会立刻红。

/// 2026-2027-1 那套课表里的全部课程标题（取自 `课表_2026-2027-1.ics`）。
const Map<String, String> _realCourses = <String, String>{
  '高等数学A(1)': '高数',
  '离散数学(1)': '离散',
  '大学外语(1)': '大英',
  '大学体育(1)': '体育',
  '大学生心理健康教育与指导': '心理',
  '思想道德与法治': '思修',
  '军事理论': '军事',
  '国家安全教育': '国安',
  '形势与政策': '形策',
  '物联网工程导论': '物联网',
  'C语言程序设计': 'C语言',
  'C语言程序设计实验': 'C实验',
};

void main() {
  group('预置表', () {
    test('真实课表的每一门课都有预置缩写，且不是规则兜底出来的', () {
      for (final entry in _realCourses.entries) {
        expect(presetAbbrFor(entry.key), entry.value,
            reason: '「${entry.key}」没落在预置表上 —— 它现在显示的是规则猜的');
      }
    });

    test('缩写都放得进格子', () {
      // 格子宽度是屏宽的七分之一，三个汉字已经是极限。预置表里出现四个字
      // 意味着那一格每节课都在缩号，而缩号之后别格的字就跟着变小。
      for (final abbr in _realCourses.values) {
        expect(abbr.length, lessThanOrEqualTo(3),
            reason: '预置缩写「$abbr」超过三个字，格子里放不下');
      }
    });

    test('两门 C 语言课不会撞成同一个缩写', () {
      // 关键词是按顺序匹配的，`C语言程序设计实验` 同时含有
      // `C语言程序设计`，顺序一错这两门课就都叫「C语言」——
      // 桌面上两门不同的课长得一模一样。
      final lab = presetAbbrFor('C语言程序设计实验');
      final lecture = presetAbbrFor('C语言程序设计');
      expect(lab, isNot(lecture));
    });

    test('带括号、带学分的叫法都能命中同一个预置', () {
      // 课名后面挂 `(1)`、`（必修）` 是常态，子串匹配正是为了吃掉这些变体。
      expect(presetAbbrFor('高等数学A(1)'), '高数');
      expect(presetAbbrFor('高等数学(上)（必修）'), '高数');
      expect(presetAbbrFor(' 大学外语(2) '), '大英');
    });
  });

  group('规则兜底', () {
    test('预置表没有的课，剥掉结尾废话再取前三个字', () {
      expect(presetAbbrFor('量子力学导论'), '量子力');
      expect(presetAbbrFor('材料力学基础'), '材料力');
    });

    test('短名字原样返回，不会为了凑字数补什么', () {
      expect(presetAbbrFor('体育'), '体育');
      expect(presetAbbrFor('金工实习'), '金工实');
    });

    test('剥完只剩一两个字时就用剥完的，不再往下削', () {
      // `大学书法基础` → 剥掉 `基础` → `大学书法` → 前三个字。
      // 但 `书法基础` → 剥掉 `基础` → `书法`，两个字就用两个字。
      expect(presetAbbrFor('书法基础'), '书法');
    });

    test('空标题不崩，给一个兜底词', () {
      expect(presetAbbrFor(''), kFallbackAbbr);
      expect(presetAbbrFor('   '), kFallbackAbbr);
    });
  });

  group('用户覆盖', () {
    test('用户写的优先于预置', () {
      expect(
        abbrFor('高等数学A(1)', overrides: {'高等数学A(1)': '数分'}),
        '数分',
      );
    });

    test('覆盖的键去空格 —— 课程标题前后带空格时仍然命中', () {
      expect(
        abbrFor('高等数学A(1)', overrides: {'  高等数学A(1)  ': '数分'}),
        '数分',
      );
    });

    test('空白的覆盖当「没写」，回落到预置', () {
      // 设置页里清空输入框的意思就是「用回预置的」。要是当成「显示成空」，
      // 用户清一下输入框会得到一个没有字的色块，而且不知道该怎么撤销。
      expect(abbrFor('高等数学A(1)', overrides: {'高等数学A(1)': ''}), '高数');
      expect(abbrFor('高等数学A(1)', overrides: {'高等数学A(1)': '   '}), '高数');
    });

    test('别的课的覆盖不会串到这门课上', () {
      expect(abbrFor('离散数学(1)', overrides: {'高等数学A(1)': '数分'}), '离散');
    });

    test('超长的覆盖被收进 kMaxAbbrChars —— 覆盖表是从磁盘读回来的', () {
      // 输入框那一侧也限了长度，但覆盖表可能来自手改过的备份文件。
      // 一个 20 字的「缩写」不会报错，只会把格子撑破。
      final long = abbrFor('某门课', overrides: {'某门课': '一二三四五六七八九十'});
      expect(long.length, kMaxAbbrChars);
      expect(long, '一二三四五六');
    });
  });

  group('课程清单', () {
    test('去重、去空、按字典序排', () {
      // 同一门课在星期一和星期五是两条模板，设置页里只该出现一次。
      expect(
        distinctCourseTitles(['离散数学(1)', '高等数学A(1)', '离散数学(1)', ' ', '']),
        ['离散数学(1)', '高等数学A(1)'].toList()..sort(),
      );
    });

    test('前后空格当成同一门课', () {
      expect(distinctCourseTitles(['军事理论', ' 军事理论 ']), ['军事理论']);
    });
  });
}
