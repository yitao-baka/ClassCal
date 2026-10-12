import 'package:classcal/data/exchange/classcal_json.dart';
import 'package:classcal/data/model/resolve.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime kWeek1 = DateTime(2026, 9, 7);
final DateTime kExportedAt = DateTime(2026, 10, 9, 12, 0, 0);

CalendarSetData sample() => CalendarSetData(
      id: 42, // 数据库主键，导出时应当被完全忽略
      name: '2026-2027-1',
      colorSeedHex: '#3F51B5',
      tabOrder: 1,
      sourceName: '学生个人课表_.xls',
      shifts: SetShifts(week1Monday: kWeek1, weekShift: 2, timeShiftMinutes: 30),
      templates: [
        CourseTemplate(
          id: 7,
          title: '高等数学A(1)',
          teacher: '张三',
          location: '一教101',
          note: '',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: [9, 5, 6, 7, 8],
          colorHex: '#E91E63',
          leadMinutes: 15,
        ),
        CourseTemplate(
          id: 8,
          title: '大学物理',
          weekday: 5,
          startPeriod: 3,
          endPeriod: 4,
          weeks: [5, 6],
        ),
      ],
      oneOffs: [
        OneOffData(
          id: 3,
          title: '讲座',
          location: '图书馆报告厅',
          date: DateTime(2026, 10, 15),
          startMinute: 19 * 60,
          endMinute: 21 * 60,
          note: '要签到',
        ),
      ],
      overrides: [
        OverrideData(
          ruleId: 8, // 指向第二条规则
          originalDate: DateTime(2026, 10, 9),
          newDate: DateTime(2026, 10, 10),
          newStartMinute: 10 * 60,
          newEndMinute: 11 * 60 + 40,
          newLocation: '三教205',
        ),
        OverrideData(
          ruleId: 7,
          originalDate: DateTime(2026, 9, 7),
          cancelled: true,
        ),
      ],
    );

String encode(CalendarSetData s) => encodeSets([s], exportedAt: kExportedAt);

void main() {
  group('往返等价', () {
    test('导出 → 导入 → 再导出，字节完全一致', () {
      // 这条比逐字段比对更强：encode 由全部数据决定，两次结果相同就意味着
      // 没有任何字段在往返中丢失或漂移。
      final once = encode(sample());
      final twice = encode(decodeSets(once).single);
      expect(twice, once);
    });

    test('往返解析出的上课时刻完全一致', () {
      final a = sample();
      final b = decodeSets(encode(a)).single;

      final ra = resolveSessions(
        shifts: a.shifts,
        templates: a.templates,
        oneOffs: a.oneOffs,
        overrides: a.overrides,
      );
      final rb = resolveSessions(
        shifts: b.shifts,
        templates: b.templates,
        oneOffs: b.oneOffs,
        overrides: b.overrides,
      );

      expect(rb.warnings, ra.warnings);
      expect(rb.sessions.length, ra.sessions.length);
      for (var i = 0; i < ra.sessions.length; i++) {
        expect(rb.sessions[i].date, ra.sessions[i].date);
        expect(rb.sessions[i].startMinute, ra.sessions[i].startMinute);
        expect(rb.sessions[i].title, ra.sessions[i].title);
        expect(rb.sessions[i].location, ra.sessions[i].location);
      }
    });

    test('套级平移能原样恢复', () {
      final b = decodeSets(encode(sample())).single;
      expect(b.shifts.weekShift, 2);
      expect(b.shifts.timeShiftMinutes, 30);
      expect(b.shifts.week1Monday, kWeek1);
    });
  });

  group('覆盖记录的引用翻译', () {
    test('覆盖指向的是数组下标，不是数据库 id', () {
      final text = encode(sample());
      final raw = decodeSets(text).single;

      // 原数据里覆盖指向 ruleId=8（第二条规则）；文件里应记成 ruleIndex=1
      expect(text, contains('"ruleIndex": 1'));

      // 导入后仍应指向第二条规则（大学物理），而不是第一条
      final second = raw.templates[1];
      expect(second.title, '大学物理');
      expect(raw.overrides.first.ruleId, second.id);
      expect(raw.overrides.first.newLocation, '三教205');
    });

    test('文件里不写数据库主键', () {
      final text = encode(sample());
      // id 42 / 7 / 8 / 3 都不该出现为 id 字段
      expect(text, isNot(contains('"id"')));
      expect(text, isNot(contains('42')));
    });

    test('指向已删除规则的孤儿覆盖记录被丢弃，不会写出坏引用', () {
      final orphaned = sample().copyWith(
        overrides: [
          OverrideData(
            ruleId: 999, // 不存在的规则
            originalDate: DateTime(2026, 9, 7),
            cancelled: true,
          ),
        ],
      );
      final text = encode(orphaned);
      expect(decodeSets(text).single.overrides, isEmpty);
    });
  });

  group('多套课表', () {
    test('多标签页各自独立往返', () {
      final a = sample();
      final b = sample().copyWith(name: '2026-2027-2', tabOrder: 2);
      final text = encodeSets([a, b], exportedAt: kExportedAt);

      final back = decodeSets(text);
      expect(back.length, 2);
      expect(back[0].name, '2026-2027-1');
      expect(back[1].name, '2026-2027-2');
      expect(back[1].tabOrder, 2);
    });

    test('空备份也能往返', () {
      final text = encodeSets(const [], exportedAt: kExportedAt);
      expect(decodeSets(text), isEmpty);
    });
  });

  group('坏输入一律明确报错', () {
    test('不是 JSON', () {
      expect(
        () => decodeSets('{ 这不是 json'),
        throwsA(isA<ClassCalFormatException>()),
      );
    });

    test('不是 ClassCal 备份', () {
      expect(
        () => decodeSets('{"format":"icalendar","version":1,"sets":[]}'),
        throwsA(
          isA<ClassCalFormatException>().having(
            (e) => e.message,
            'message',
            contains('format'),
          ),
        ),
      );
    });

    test('来自更新的格式版本 —— 拒绝而不是猜着读', () {
      expect(
        () => decodeSets(
          '{"format":"classcal","version":${kClassCalJsonVersion + 1},"sets":[]}',
        ),
        throwsA(
          isA<ClassCalFormatException>().having(
            (e) => e.message,
            'message',
            contains('更新的版本'),
          ),
        ),
      );
    });

    test('weekday 越界时报错并给出字段路径', () {
      final bad = encode(sample()).replaceFirst('"weekday": 1', '"weekday": 9');
      expect(
        () => decodeSets(bad),
        throwsA(
          isA<ClassCalFormatException>()
              .having((e) => e.path, 'path', contains('weekday')),
        ),
      );
    });

    test('不存在的日期被拒绝，不会被 DateTime 悄悄滚到三月', () {
      final bad = encode(sample()).replaceFirst('2026-10-15', '2026-02-31');
      expect(
        () => decodeSets(bad),
        throwsA(
          isA<ClassCalFormatException>().having(
            (e) => e.message,
            'message',
            contains('不存在'),
          ),
        ),
      );
    });

    test('覆盖记录指向不存在的下标时报错', () {
      final bad = encode(sample()).replaceFirst('"ruleIndex": 1', '"ruleIndex": 77');
      expect(
        () => decodeSets(bad),
        throwsA(
          isA<ClassCalFormatException>().having(
            (e) => e.path,
            'path',
            contains('overrides[0]'),
          ),
        ),
      );
    });

    test('未知的多余字段被忽略，不阻挡读取（向前兼容）', () {
      final text = encode(sample()).replaceFirst(
        '"sets": [',
        '"futureField": {"a": 1},\n  "sets": [',
      );
      expect(decodeSets(text).single.name, '2026-2027-1');
    });
  });
}
