/// ClassCal 自有 JSON 格式 —— 无损备份与恢复。
///
/// 与 ICS 的分工：ICS 负责和别的日历软件互通，必然是**有损**的（周次、节次
/// 在标准里没有位置，只能塞进 DESCRIPTION 当人看的文本）；这个格式负责在本
/// App 内部完整还原，包括编辑记录和套级平移这类 ICS 表达不了的状态。
///
/// 纯 Dart，不碰 drift / Flutter，因此「导出再导入应当等价」这条可以用
/// 普通单元测试直接验证，不需要起数据库。
library;

import 'dart:convert';

import '../model/domain.dart';

/// 当前格式版本。加字段时递增，旧文件仍可读。
const int kClassCalJsonVersion = 1;
const String kClassCalFormatTag = 'classcal';

/// 文件格式不对时抛出。
class ClassCalFormatException implements Exception {
  ClassCalFormatException(this.message, [this.path]);
  final String message;

  /// 出问题的字段路径，例如 `sets[0].rules[3].weekday`，便于定位。
  final String? path;

  @override
  String toString() =>
      'ClassCalFormatException: $message${path == null ? '' : ' @ $path'}';
}

// ---------------------------------------------------------------------------
// 编码
// ---------------------------------------------------------------------------

/// 把若干套课表编成 JSON 文本。
///
/// 注意**不写数据库主键**：overrides 指向 rule 用的是数组下标而不是 id。
/// 因为 id 是数据库自增的、导入到别处必然重排，存进去只会产生一份
/// 看着像有效、实际指向错误课程的引用。下标在同一次导出内稳定，导入时
/// 一边建规则一边记「旧下标 → 新 id」即可正确还原。
String encodeSets(List<CalendarSetData> sets, {DateTime? exportedAt}) {
  final root = <String, Object?>{
    'format': kClassCalFormatTag,
    'version': kClassCalJsonVersion,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'sets': sets.map(_encodeSet).toList(),
  };
  // pretty 输出：备份文件是给人看和手工改的，多出来的字节不值得省。
  return const JsonEncoder.withIndent('  ').convert(root);
}

Map<String, Object?> _encodeSet(CalendarSetData s) {
  // 规则 id → 数组下标。override 存的是下标而不是 id，这一步是必需的翻译，
  // 少了它导出的备份会指向看似有效、实际全错的课程。
  final indexOfRule = <int, int>{
    for (var i = 0; i < s.templates.length; i++) s.templates[i].id: i,
  };

  return <String, Object?>{
    'name': s.name,
    'colorSeedHex': s.colorSeedHex,
    'tabOrder': s.tabOrder,
    'visible': s.visible,
    if (s.sourceName != null) 'sourceName': s.sourceName,
    'week1Monday': _date(s.shifts.week1Monday),
    'weekShift': s.shifts.weekShift,
    'timeShiftMinutes': s.shifts.timeShiftMinutes,
    'rules': s.templates.map(_encodeRule).toList(),
    'oneOffs': s.oneOffs.map(_encodeOneOff).toList(),
    // 指向已不存在的规则的覆盖记录直接丢弃 —— 规则没了，这条改动就没有意义。
    // 库里外键带 ON DELETE CASCADE，正常情况下不会有这种孤儿行。
    'overrides': <Map<String, Object?>>[
      for (final o in s.overrides)
        if (indexOfRule[o.ruleId] != null) _encodeOverride(o, indexOfRule[o.ruleId]!),
    ],
  };
}

Map<String, Object?> _encodeRule(CourseTemplate t) => <String, Object?>{
      'title': t.title,
      'teacher': t.teacher,
      'location': t.location,
      'note': t.note,
      if (t.colorHex != null) 'colorOverrideHex': t.colorHex,
      'weekday': t.weekday,
      'startPeriod': t.startPeriod,
      'endPeriod': t.endPeriod,
      'weeks': (t.weeks.toList()..sort()),
      'remindersEnabled': t.remindersEnabled,
      if (t.leadMinutes != null) 'leadMinutes': t.leadMinutes,
    };

Map<String, Object?> _encodeOneOff(OneOffData e) => <String, Object?>{
      'title': e.title,
      'location': e.location,
      'note': e.note,
      if (e.colorHex != null) 'colorHex': e.colorHex,
      'date': _date(e.date),
      // 用「距当日 00:00 的分钟数」而不是 ISO 时刻：分钟数是纯量、
      // 无时区歧义，也不会被跨时区恢复搞成前一天晚上。
      'startMinute': e.startMinute,
      'endMinute': e.endMinute,
    };

Map<String, Object?> _encodeOverride(OverrideData o, int ruleIndex) => <String, Object?>{
      'ruleIndex': ruleIndex,
      'originalDate': _date(o.originalDate),
      'cancelled': o.cancelled,
      if (o.newDate != null) 'newDate': _date(o.newDate!),
      if (o.newStartMinute != null) 'newStartMinute': o.newStartMinute,
      if (o.newEndMinute != null) 'newEndMinute': o.newEndMinute,
      if (o.newLocation != null) 'newLocation': o.newLocation,
      if (o.newTitle != null) 'newTitle': o.newTitle,
    };

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// 解码
// ---------------------------------------------------------------------------

/// 解析 JSON 文本。
///
/// 对结构性错误**抛异常而不是跳过** —— 这是「完整备份」，静默丢数据比
/// 明确报错糟糕得多。可选的展示字段缺失才走默认值。
///
/// 返回的 [CourseTemplate.id] / [OneOffData.id] 是**文件内的局部编号
/// （下标 + 1）**，不是数据库主键；[OverrideData.ruleId] 引用的是同一套
/// 局部编号，因此返回的对象图内部自洽、可直接喂给 `resolveSessions`。
/// 落库时由仓库层建立「局部编号 → 真实主键」的映射整体重编。
List<CalendarSetData> decodeSets(String source) {
  final Object? root;
  try {
    root = jsonDecode(source);
  } on FormatException catch (e) {
    throw ClassCalFormatException('不是合法的 JSON：${e.message}');
  }

  final map = _asMap(root, '');
  final format = map['format'];
  if (format != kClassCalFormatTag) {
    throw ClassCalFormatException('不是 ClassCal 备份文件（format=$format）');
  }
  final version = _asInt(map['version'], 'version');
  if (version > kClassCalJsonVersion) {
    throw ClassCalFormatException(
      '备份来自更新的版本（文件 v$version，本程序支持到 v$kClassCalJsonVersion）',
    );
  }

  final rawSets = _asList(map['sets'], 'sets');
  return <CalendarSetData>[
    for (var i = 0; i < rawSets.length; i++) _decodeSet(rawSets[i], 'sets[$i]'),
  ];
}

CalendarSetData _decodeSet(Object? raw, String path) {
  final m = _asMap(raw, path);
  final rawRules = _asList(m['rules'] ?? const [], '$path.rules');
  final rawOverrides = _asList(m['overrides'] ?? const [], '$path.overrides');

  // 必须先建规则，才能把 override 的数组下标翻译成规则 id。
  final rules = <CourseTemplate>[
    for (var i = 0; i < rawRules.length; i++) _decodeRule(rawRules[i], '$path.rules[$i]', i),
  ];
  // 下标 → 新建的规则 id。这里直接把「下标」当作 id 用，因为在「一套课表」
  // 这个作用域内它本来就是唯一且稳定的；落库时仓库层会整批重映射。
  final indexToRuleId = <int, int>{for (var i = 0; i < rules.length; i++) i: rules[i].id};

  final overrides = <OverrideData>[];
  for (var i = 0; i < rawOverrides.length; i++) {
    final p = '$path.overrides[$i]';
    final om = _asMap(rawOverrides[i], p);
    final idx = _asInt(om['ruleIndex'], '$p.ruleIndex');
    final ruleId = indexToRuleId[idx];
    if (ruleId == null) {
      throw ClassCalFormatException('覆盖记录指向不存在的规则下标 $idx', p);
    }
    overrides.add(
      OverrideData(
        ruleId: ruleId,
        originalDate: _asDate(om['originalDate'], '$p.originalDate'),
        cancelled: _asBool(om['cancelled'], '$p.cancelled', fallback: false),
        newDate: om['newDate'] == null ? null : _asDate(om['newDate'], '$p.newDate'),
        newStartMinute: _optMinute(om['newStartMinute'], '$p.newStartMinute'),
        newEndMinute: _optMinute(om['newEndMinute'], '$p.newEndMinute'),
        newLocation: om['newLocation'] as String?,
        newTitle: om['newTitle'] as String?,
      ),
    );
  }

  final rawOneOffs = _asList(m['oneOffs'] ?? const [], '$path.oneOffs');
  final oneOffs = <OneOffData>[
    for (var i = 0; i < rawOneOffs.length; i++) _decodeOneOff(rawOneOffs[i], '$path.oneOffs[$i]', i),
  ];

  return CalendarSetData(
    id: CalendarSetData.unsavedId,
    name: _asString(m['name'], '$path.name', fallback: '未命名课表'),
    colorSeedHex: _asString(m['colorSeedHex'], '$path.colorSeedHex', fallback: '#6750A4'),
    tabOrder: _asInt(m['tabOrder'], '$path.tabOrder', fallback: 0),
    visible: _asBool(m['visible'], '$path.visible', fallback: true),
    sourceName: m['sourceName'] as String?,
    shifts: SetShifts(
      week1Monday: _asDate(m['week1Monday'], '$path.week1Monday'),
      weekShift: _asInt(m['weekShift'], '$path.weekShift', fallback: 0),
      timeShiftMinutes: _asInt(m['timeShiftMinutes'], '$path.timeShiftMinutes', fallback: 0),
    ),
    templates: rules,
    oneOffs: oneOffs,
    overrides: overrides,
  );
}

CourseTemplate _decodeRule(Object? raw, String path, int index) {
  final m = _asMap(raw, path);
  final weekday = _asInt(m['weekday'], '$path.weekday');
  if (weekday < 1 || weekday > 7) {
    throw ClassCalFormatException('weekday 必须在 1..7，实际为 $weekday', '$path.weekday');
  }
  final startPeriod = _asInt(m['startPeriod'], '$path.startPeriod');
  final endPeriod = _asInt(m['endPeriod'], '$path.endPeriod', fallback: startPeriod);
  if (startPeriod < 1 || endPeriod < startPeriod) {
    throw ClassCalFormatException(
      '节次区间非法：$startPeriod-$endPeriod',
      '$path.startPeriod',
    );
  }

  final rawWeeks = _asList(m['weeks'] ?? const [], '$path.weeks');
  final weeks = <int>{};
  for (var i = 0; i < rawWeeks.length; i++) {
    final w = _asInt(rawWeeks[i], '$path.weeks[$i]');
    if (w > 0) weeks.add(w);
  }

  return CourseTemplate(
    // 用「下标 + 1」当规则 id：既保证同一套内唯一，又让 override 的下标
    // 翻译成为恒等映射，少一层容易写错的表。
    id: index + 1,
    title: _asString(m['title'], '$path.title', fallback: '未命名'),
    teacher: _asString(m['teacher'], '$path.teacher', fallback: ''),
    location: _asString(m['location'], '$path.location', fallback: ''),
    note: _asString(m['note'], '$path.note', fallback: ''),
    colorHex: m['colorOverrideHex'] as String?,
    weekday: weekday,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    weeks: weeks.toList()..sort(),
    remindersEnabled: _asBool(m['remindersEnabled'], '$path.remindersEnabled', fallback: true),
    leadMinutes: m['leadMinutes'] == null
        ? null
        : _asInt(m['leadMinutes'], '$path.leadMinutes'),
  );
}

OneOffData _decodeOneOff(Object? raw, String path, int index) {
  final m = _asMap(raw, path);
  final start = _asMinute(m['startMinute'], '$path.startMinute');
  final end = _asMinute(m['endMinute'], '$path.endMinute', fallback: start);
  return OneOffData(
    id: index + 1,
    title: _asString(m['title'], '$path.title', fallback: '未命名'),
    location: _asString(m['location'], '$path.location', fallback: ''),
    note: _asString(m['note'], '$path.note', fallback: ''),
    colorHex: m['colorHex'] as String?,
    date: _asDate(m['date'], '$path.date'),
    startMinute: start,
    endMinute: end,
  );
}

// ---------------------------------------------------------------------------
// 取值助手 —— 统一给出带路径的报错
// ---------------------------------------------------------------------------

Map<String, Object?> _asMap(Object? v, String path) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw ClassCalFormatException('应为对象，实际为 ${v.runtimeType}', path.isEmpty ? 'root' : path);
}

List<Object?> _asList(Object? v, String path) {
  if (v is List) return v;
  throw ClassCalFormatException('应为数组，实际为 ${v.runtimeType}', path);
}

String _asString(Object? v, String path, {String? fallback}) {
  if (v == null && fallback != null) return fallback;
  if (v is String) return v;
  throw ClassCalFormatException('应为字符串，实际为 ${v.runtimeType}', path);
}

int _asInt(Object? v, String path, {int? fallback}) {
  if (v == null && fallback != null) return fallback;
  if (v is int) return v;
  // JSON 里 5.0 也是合法写法，宽容接受
  if (v is double && v == v.roundToDouble()) return v.toInt();
  throw ClassCalFormatException('应为整数，实际为 ${v.runtimeType}', path);
}

bool _asBool(Object? v, String path, {required bool fallback}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  throw ClassCalFormatException('应为布尔值，实际为 ${v.runtimeType}', path);
}

int _asMinute(Object? v, String path, {int? fallback}) {
  final m = _asInt(v, path, fallback: fallback);
  if (m < 0 || m > 24 * 60) {
    throw ClassCalFormatException('分钟数应在 0..1440，实际为 $m', path);
  }
  return m;
}

int? _optMinute(Object? v, String path) => v == null ? null : _asMinute(v, path);

/// 解析 `2026-09-07`。刻意不接受带时分秒的写法 —— 导出端不产生，出现即是文件坏了。
DateTime _asDate(Object? v, String path) {
  final s = _asString(v, path);
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) {
    throw ClassCalFormatException('日期应为 yyyy-MM-dd，实际为 "$s"', path);
  }
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final dt = DateTime(y, mo, d);
  // DateTime 会把 2026-02-31 滚成 3 月 3 日，必须回查
  if (dt.year != y || dt.month != mo || dt.day != d) {
    throw ClassCalFormatException('日期不存在："$s"', path);
  }
  return dt;
}
