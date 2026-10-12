// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CalendarSetsTable extends CalendarSets
    with TableInfo<$CalendarSetsTable, CalendarSet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalendarSetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorSeedHexMeta = const VerificationMeta(
    'colorSeedHex',
  );
  @override
  late final GeneratedColumn<String> colorSeedHex = GeneratedColumn<String>(
    'color_seed_hex',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#6750A4'),
  );
  static const VerificationMeta _tabOrderMeta = const VerificationMeta(
    'tabOrder',
  );
  @override
  late final GeneratedColumn<int> tabOrder = GeneratedColumn<int>(
    'tab_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _week1MondayMeta = const VerificationMeta(
    'week1Monday',
  );
  @override
  late final GeneratedColumn<DateTime> week1Monday = GeneratedColumn<DateTime>(
    'week1_monday',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _visibleMeta = const VerificationMeta(
    'visible',
  );
  @override
  late final GeneratedColumn<bool> visible = GeneratedColumn<bool>(
    'visible',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("visible" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _weekShiftMeta = const VerificationMeta(
    'weekShift',
  );
  @override
  late final GeneratedColumn<int> weekShift = GeneratedColumn<int>(
    'week_shift',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _timeShiftMinutesMeta = const VerificationMeta(
    'timeShiftMinutes',
  );
  @override
  late final GeneratedColumn<int> timeShiftMinutes = GeneratedColumn<int>(
    'time_shift_minutes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    colorSeedHex,
    tabOrder,
    week1Monday,
    visible,
    weekShift,
    timeShiftMinutes,
    sourceName,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_sets';
  @override
  VerificationContext validateIntegrity(
    Insertable<CalendarSet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_seed_hex')) {
      context.handle(
        _colorSeedHexMeta,
        colorSeedHex.isAcceptableOrUnknown(
          data['color_seed_hex']!,
          _colorSeedHexMeta,
        ),
      );
    }
    if (data.containsKey('tab_order')) {
      context.handle(
        _tabOrderMeta,
        tabOrder.isAcceptableOrUnknown(data['tab_order']!, _tabOrderMeta),
      );
    }
    if (data.containsKey('week1_monday')) {
      context.handle(
        _week1MondayMeta,
        week1Monday.isAcceptableOrUnknown(
          data['week1_monday']!,
          _week1MondayMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_week1MondayMeta);
    }
    if (data.containsKey('visible')) {
      context.handle(
        _visibleMeta,
        visible.isAcceptableOrUnknown(data['visible']!, _visibleMeta),
      );
    }
    if (data.containsKey('week_shift')) {
      context.handle(
        _weekShiftMeta,
        weekShift.isAcceptableOrUnknown(data['week_shift']!, _weekShiftMeta),
      );
    }
    if (data.containsKey('time_shift_minutes')) {
      context.handle(
        _timeShiftMinutesMeta,
        timeShiftMinutes.isAcceptableOrUnknown(
          data['time_shift_minutes']!,
          _timeShiftMinutesMeta,
        ),
      );
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CalendarSet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalendarSet(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorSeedHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_seed_hex'],
      )!,
      tabOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tab_order'],
      )!,
      week1Monday: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}week1_monday'],
      )!,
      visible: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}visible'],
      )!,
      weekShift: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}week_shift'],
      )!,
      timeShiftMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_shift_minutes'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CalendarSetsTable createAlias(String alias) {
    return $CalendarSetsTable(attachedDatabase, alias);
  }
}

class CalendarSet extends DataClass implements Insertable<CalendarSet> {
  final int id;
  final String name;
  final String colorSeedHex;
  final int tabOrder;

  /// 该套课表第 1 周的周一 —— 全部日期换算的锚点。
  ///
  /// 导入时由用户确认（ICS 里的周次信息本身不含年份），存下来避免每次渲染重算。
  final DateTime week1Monday;
  final bool visible;

  /// 整体前后移动的周数，可负。
  final int weekShift;

  /// 整体前后移动的分钟数，可负。与 [weekShift] 是两条正交的时间轴。
  final int timeShiftMinutes;

  /// 导入来源文件名，便于追溯「这套课表是哪来的」。
  final String? sourceName;
  final DateTime createdAt;
  const CalendarSet({
    required this.id,
    required this.name,
    required this.colorSeedHex,
    required this.tabOrder,
    required this.week1Monday,
    required this.visible,
    required this.weekShift,
    required this.timeShiftMinutes,
    this.sourceName,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color_seed_hex'] = Variable<String>(colorSeedHex);
    map['tab_order'] = Variable<int>(tabOrder);
    map['week1_monday'] = Variable<DateTime>(week1Monday);
    map['visible'] = Variable<bool>(visible);
    map['week_shift'] = Variable<int>(weekShift);
    map['time_shift_minutes'] = Variable<int>(timeShiftMinutes);
    if (!nullToAbsent || sourceName != null) {
      map['source_name'] = Variable<String>(sourceName);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CalendarSetsCompanion toCompanion(bool nullToAbsent) {
    return CalendarSetsCompanion(
      id: Value(id),
      name: Value(name),
      colorSeedHex: Value(colorSeedHex),
      tabOrder: Value(tabOrder),
      week1Monday: Value(week1Monday),
      visible: Value(visible),
      weekShift: Value(weekShift),
      timeShiftMinutes: Value(timeShiftMinutes),
      sourceName: sourceName == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceName),
      createdAt: Value(createdAt),
    );
  }

  factory CalendarSet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalendarSet(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorSeedHex: serializer.fromJson<String>(json['colorSeedHex']),
      tabOrder: serializer.fromJson<int>(json['tabOrder']),
      week1Monday: serializer.fromJson<DateTime>(json['week1Monday']),
      visible: serializer.fromJson<bool>(json['visible']),
      weekShift: serializer.fromJson<int>(json['weekShift']),
      timeShiftMinutes: serializer.fromJson<int>(json['timeShiftMinutes']),
      sourceName: serializer.fromJson<String?>(json['sourceName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'colorSeedHex': serializer.toJson<String>(colorSeedHex),
      'tabOrder': serializer.toJson<int>(tabOrder),
      'week1Monday': serializer.toJson<DateTime>(week1Monday),
      'visible': serializer.toJson<bool>(visible),
      'weekShift': serializer.toJson<int>(weekShift),
      'timeShiftMinutes': serializer.toJson<int>(timeShiftMinutes),
      'sourceName': serializer.toJson<String?>(sourceName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CalendarSet copyWith({
    int? id,
    String? name,
    String? colorSeedHex,
    int? tabOrder,
    DateTime? week1Monday,
    bool? visible,
    int? weekShift,
    int? timeShiftMinutes,
    Value<String?> sourceName = const Value.absent(),
    DateTime? createdAt,
  }) => CalendarSet(
    id: id ?? this.id,
    name: name ?? this.name,
    colorSeedHex: colorSeedHex ?? this.colorSeedHex,
    tabOrder: tabOrder ?? this.tabOrder,
    week1Monday: week1Monday ?? this.week1Monday,
    visible: visible ?? this.visible,
    weekShift: weekShift ?? this.weekShift,
    timeShiftMinutes: timeShiftMinutes ?? this.timeShiftMinutes,
    sourceName: sourceName.present ? sourceName.value : this.sourceName,
    createdAt: createdAt ?? this.createdAt,
  );
  CalendarSet copyWithCompanion(CalendarSetsCompanion data) {
    return CalendarSet(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorSeedHex: data.colorSeedHex.present
          ? data.colorSeedHex.value
          : this.colorSeedHex,
      tabOrder: data.tabOrder.present ? data.tabOrder.value : this.tabOrder,
      week1Monday: data.week1Monday.present
          ? data.week1Monday.value
          : this.week1Monday,
      visible: data.visible.present ? data.visible.value : this.visible,
      weekShift: data.weekShift.present ? data.weekShift.value : this.weekShift,
      timeShiftMinutes: data.timeShiftMinutes.present
          ? data.timeShiftMinutes.value
          : this.timeShiftMinutes,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalendarSet(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorSeedHex: $colorSeedHex, ')
          ..write('tabOrder: $tabOrder, ')
          ..write('week1Monday: $week1Monday, ')
          ..write('visible: $visible, ')
          ..write('weekShift: $weekShift, ')
          ..write('timeShiftMinutes: $timeShiftMinutes, ')
          ..write('sourceName: $sourceName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    colorSeedHex,
    tabOrder,
    week1Monday,
    visible,
    weekShift,
    timeShiftMinutes,
    sourceName,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendarSet &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorSeedHex == this.colorSeedHex &&
          other.tabOrder == this.tabOrder &&
          other.week1Monday == this.week1Monday &&
          other.visible == this.visible &&
          other.weekShift == this.weekShift &&
          other.timeShiftMinutes == this.timeShiftMinutes &&
          other.sourceName == this.sourceName &&
          other.createdAt == this.createdAt);
}

class CalendarSetsCompanion extends UpdateCompanion<CalendarSet> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> colorSeedHex;
  final Value<int> tabOrder;
  final Value<DateTime> week1Monday;
  final Value<bool> visible;
  final Value<int> weekShift;
  final Value<int> timeShiftMinutes;
  final Value<String?> sourceName;
  final Value<DateTime> createdAt;
  const CalendarSetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorSeedHex = const Value.absent(),
    this.tabOrder = const Value.absent(),
    this.week1Monday = const Value.absent(),
    this.visible = const Value.absent(),
    this.weekShift = const Value.absent(),
    this.timeShiftMinutes = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CalendarSetsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.colorSeedHex = const Value.absent(),
    this.tabOrder = const Value.absent(),
    required DateTime week1Monday,
    this.visible = const Value.absent(),
    this.weekShift = const Value.absent(),
    this.timeShiftMinutes = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name),
       week1Monday = Value(week1Monday);
  static Insertable<CalendarSet> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? colorSeedHex,
    Expression<int>? tabOrder,
    Expression<DateTime>? week1Monday,
    Expression<bool>? visible,
    Expression<int>? weekShift,
    Expression<int>? timeShiftMinutes,
    Expression<String>? sourceName,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorSeedHex != null) 'color_seed_hex': colorSeedHex,
      if (tabOrder != null) 'tab_order': tabOrder,
      if (week1Monday != null) 'week1_monday': week1Monday,
      if (visible != null) 'visible': visible,
      if (weekShift != null) 'week_shift': weekShift,
      if (timeShiftMinutes != null) 'time_shift_minutes': timeShiftMinutes,
      if (sourceName != null) 'source_name': sourceName,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CalendarSetsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? colorSeedHex,
    Value<int>? tabOrder,
    Value<DateTime>? week1Monday,
    Value<bool>? visible,
    Value<int>? weekShift,
    Value<int>? timeShiftMinutes,
    Value<String?>? sourceName,
    Value<DateTime>? createdAt,
  }) {
    return CalendarSetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorSeedHex: colorSeedHex ?? this.colorSeedHex,
      tabOrder: tabOrder ?? this.tabOrder,
      week1Monday: week1Monday ?? this.week1Monday,
      visible: visible ?? this.visible,
      weekShift: weekShift ?? this.weekShift,
      timeShiftMinutes: timeShiftMinutes ?? this.timeShiftMinutes,
      sourceName: sourceName ?? this.sourceName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorSeedHex.present) {
      map['color_seed_hex'] = Variable<String>(colorSeedHex.value);
    }
    if (tabOrder.present) {
      map['tab_order'] = Variable<int>(tabOrder.value);
    }
    if (week1Monday.present) {
      map['week1_monday'] = Variable<DateTime>(week1Monday.value);
    }
    if (visible.present) {
      map['visible'] = Variable<bool>(visible.value);
    }
    if (weekShift.present) {
      map['week_shift'] = Variable<int>(weekShift.value);
    }
    if (timeShiftMinutes.present) {
      map['time_shift_minutes'] = Variable<int>(timeShiftMinutes.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalendarSetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorSeedHex: $colorSeedHex, ')
          ..write('tabOrder: $tabOrder, ')
          ..write('week1Monday: $week1Monday, ')
          ..write('visible: $visible, ')
          ..write('weekShift: $weekShift, ')
          ..write('timeShiftMinutes: $timeShiftMinutes, ')
          ..write('sourceName: $sourceName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CourseRulesTable extends CourseRules
    with TableInfo<$CourseRulesTable, CourseRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _setIdMeta = const VerificationMeta('setId');
  @override
  late final GeneratedColumn<int> setId = GeneratedColumn<int>(
    'set_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES calendar_sets (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _teacherMeta = const VerificationMeta(
    'teacher',
  );
  @override
  late final GeneratedColumn<String> teacher = GeneratedColumn<String>(
    'teacher',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorOverrideHexMeta = const VerificationMeta(
    'colorOverrideHex',
  );
  @override
  late final GeneratedColumn<String> colorOverrideHex = GeneratedColumn<String>(
    'color_override_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startPeriodMeta = const VerificationMeta(
    'startPeriod',
  );
  @override
  late final GeneratedColumn<int> startPeriod = GeneratedColumn<int>(
    'start_period',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endPeriodMeta = const VerificationMeta(
    'endPeriod',
  );
  @override
  late final GeneratedColumn<int> endPeriod = GeneratedColumn<int>(
    'end_period',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<int>, String> weeks =
      GeneratedColumn<String>(
        'weeks',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<int>>($CourseRulesTable.$converterweeks);
  static const VerificationMeta _remindersEnabledMeta = const VerificationMeta(
    'remindersEnabled',
  );
  @override
  late final GeneratedColumn<bool> remindersEnabled = GeneratedColumn<bool>(
    'reminders_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reminders_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _leadMinutesMeta = const VerificationMeta(
    'leadMinutes',
  );
  @override
  late final GeneratedColumn<int> leadMinutes = GeneratedColumn<int>(
    'lead_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    setId,
    title,
    teacher,
    location,
    colorOverrideHex,
    note,
    weekday,
    startPeriod,
    endPeriod,
    weeks,
    remindersEnabled,
    leadMinutes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<CourseRule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('set_id')) {
      context.handle(
        _setIdMeta,
        setId.isAcceptableOrUnknown(data['set_id']!, _setIdMeta),
      );
    } else if (isInserting) {
      context.missing(_setIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('teacher')) {
      context.handle(
        _teacherMeta,
        teacher.isAcceptableOrUnknown(data['teacher']!, _teacherMeta),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('color_override_hex')) {
      context.handle(
        _colorOverrideHexMeta,
        colorOverrideHex.isAcceptableOrUnknown(
          data['color_override_hex']!,
          _colorOverrideHexMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('start_period')) {
      context.handle(
        _startPeriodMeta,
        startPeriod.isAcceptableOrUnknown(
          data['start_period']!,
          _startPeriodMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startPeriodMeta);
    }
    if (data.containsKey('end_period')) {
      context.handle(
        _endPeriodMeta,
        endPeriod.isAcceptableOrUnknown(data['end_period']!, _endPeriodMeta),
      );
    } else if (isInserting) {
      context.missing(_endPeriodMeta);
    }
    if (data.containsKey('reminders_enabled')) {
      context.handle(
        _remindersEnabledMeta,
        remindersEnabled.isAcceptableOrUnknown(
          data['reminders_enabled']!,
          _remindersEnabledMeta,
        ),
      );
    }
    if (data.containsKey('lead_minutes')) {
      context.handle(
        _leadMinutesMeta,
        leadMinutes.isAcceptableOrUnknown(
          data['lead_minutes']!,
          _leadMinutesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CourseRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseRule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      setId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}set_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      teacher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teacher'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      )!,
      colorOverrideHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_override_hex'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      startPeriod: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_period'],
      )!,
      endPeriod: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_period'],
      )!,
      weeks: $CourseRulesTable.$converterweeks.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}weeks'],
        )!,
      ),
      remindersEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reminders_enabled'],
      )!,
      leadMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lead_minutes'],
      ),
    );
  }

  @override
  $CourseRulesTable createAlias(String alias) {
    return $CourseRulesTable(attachedDatabase, alias);
  }

  static TypeConverter<List<int>, String> $converterweeks =
      const IntListConverter();
}

class CourseRule extends DataClass implements Insertable<CourseRule> {
  final int id;
  final int setId;
  final String title;
  final String teacher;
  final String location;

  /// 手动指定的课程颜色；null 表示按 [title] 哈希自动分配。
  final String? colorOverrideHex;
  final String note;

  /// 1=周一 … 7=周日。
  final int weekday;

  /// 起始 / 结束节次（1-based，含）。「第一二节」是 1..2。
  final int startPeriod;
  final int endPeriod;

  /// 上课周次，展开集合。
  final List<int> weeks;
  final bool remindersEnabled;

  /// 提前多少分钟提醒；null 表示沿用全局默认。
  final int? leadMinutes;
  const CourseRule({
    required this.id,
    required this.setId,
    required this.title,
    required this.teacher,
    required this.location,
    this.colorOverrideHex,
    required this.note,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    required this.remindersEnabled,
    this.leadMinutes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['set_id'] = Variable<int>(setId);
    map['title'] = Variable<String>(title);
    map['teacher'] = Variable<String>(teacher);
    map['location'] = Variable<String>(location);
    if (!nullToAbsent || colorOverrideHex != null) {
      map['color_override_hex'] = Variable<String>(colorOverrideHex);
    }
    map['note'] = Variable<String>(note);
    map['weekday'] = Variable<int>(weekday);
    map['start_period'] = Variable<int>(startPeriod);
    map['end_period'] = Variable<int>(endPeriod);
    {
      map['weeks'] = Variable<String>(
        $CourseRulesTable.$converterweeks.toSql(weeks),
      );
    }
    map['reminders_enabled'] = Variable<bool>(remindersEnabled);
    if (!nullToAbsent || leadMinutes != null) {
      map['lead_minutes'] = Variable<int>(leadMinutes);
    }
    return map;
  }

  CourseRulesCompanion toCompanion(bool nullToAbsent) {
    return CourseRulesCompanion(
      id: Value(id),
      setId: Value(setId),
      title: Value(title),
      teacher: Value(teacher),
      location: Value(location),
      colorOverrideHex: colorOverrideHex == null && nullToAbsent
          ? const Value.absent()
          : Value(colorOverrideHex),
      note: Value(note),
      weekday: Value(weekday),
      startPeriod: Value(startPeriod),
      endPeriod: Value(endPeriod),
      weeks: Value(weeks),
      remindersEnabled: Value(remindersEnabled),
      leadMinutes: leadMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(leadMinutes),
    );
  }

  factory CourseRule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseRule(
      id: serializer.fromJson<int>(json['id']),
      setId: serializer.fromJson<int>(json['setId']),
      title: serializer.fromJson<String>(json['title']),
      teacher: serializer.fromJson<String>(json['teacher']),
      location: serializer.fromJson<String>(json['location']),
      colorOverrideHex: serializer.fromJson<String?>(json['colorOverrideHex']),
      note: serializer.fromJson<String>(json['note']),
      weekday: serializer.fromJson<int>(json['weekday']),
      startPeriod: serializer.fromJson<int>(json['startPeriod']),
      endPeriod: serializer.fromJson<int>(json['endPeriod']),
      weeks: serializer.fromJson<List<int>>(json['weeks']),
      remindersEnabled: serializer.fromJson<bool>(json['remindersEnabled']),
      leadMinutes: serializer.fromJson<int?>(json['leadMinutes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'setId': serializer.toJson<int>(setId),
      'title': serializer.toJson<String>(title),
      'teacher': serializer.toJson<String>(teacher),
      'location': serializer.toJson<String>(location),
      'colorOverrideHex': serializer.toJson<String?>(colorOverrideHex),
      'note': serializer.toJson<String>(note),
      'weekday': serializer.toJson<int>(weekday),
      'startPeriod': serializer.toJson<int>(startPeriod),
      'endPeriod': serializer.toJson<int>(endPeriod),
      'weeks': serializer.toJson<List<int>>(weeks),
      'remindersEnabled': serializer.toJson<bool>(remindersEnabled),
      'leadMinutes': serializer.toJson<int?>(leadMinutes),
    };
  }

  CourseRule copyWith({
    int? id,
    int? setId,
    String? title,
    String? teacher,
    String? location,
    Value<String?> colorOverrideHex = const Value.absent(),
    String? note,
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    List<int>? weeks,
    bool? remindersEnabled,
    Value<int?> leadMinutes = const Value.absent(),
  }) => CourseRule(
    id: id ?? this.id,
    setId: setId ?? this.setId,
    title: title ?? this.title,
    teacher: teacher ?? this.teacher,
    location: location ?? this.location,
    colorOverrideHex: colorOverrideHex.present
        ? colorOverrideHex.value
        : this.colorOverrideHex,
    note: note ?? this.note,
    weekday: weekday ?? this.weekday,
    startPeriod: startPeriod ?? this.startPeriod,
    endPeriod: endPeriod ?? this.endPeriod,
    weeks: weeks ?? this.weeks,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    leadMinutes: leadMinutes.present ? leadMinutes.value : this.leadMinutes,
  );
  CourseRule copyWithCompanion(CourseRulesCompanion data) {
    return CourseRule(
      id: data.id.present ? data.id.value : this.id,
      setId: data.setId.present ? data.setId.value : this.setId,
      title: data.title.present ? data.title.value : this.title,
      teacher: data.teacher.present ? data.teacher.value : this.teacher,
      location: data.location.present ? data.location.value : this.location,
      colorOverrideHex: data.colorOverrideHex.present
          ? data.colorOverrideHex.value
          : this.colorOverrideHex,
      note: data.note.present ? data.note.value : this.note,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      startPeriod: data.startPeriod.present
          ? data.startPeriod.value
          : this.startPeriod,
      endPeriod: data.endPeriod.present ? data.endPeriod.value : this.endPeriod,
      weeks: data.weeks.present ? data.weeks.value : this.weeks,
      remindersEnabled: data.remindersEnabled.present
          ? data.remindersEnabled.value
          : this.remindersEnabled,
      leadMinutes: data.leadMinutes.present
          ? data.leadMinutes.value
          : this.leadMinutes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseRule(')
          ..write('id: $id, ')
          ..write('setId: $setId, ')
          ..write('title: $title, ')
          ..write('teacher: $teacher, ')
          ..write('location: $location, ')
          ..write('colorOverrideHex: $colorOverrideHex, ')
          ..write('note: $note, ')
          ..write('weekday: $weekday, ')
          ..write('startPeriod: $startPeriod, ')
          ..write('endPeriod: $endPeriod, ')
          ..write('weeks: $weeks, ')
          ..write('remindersEnabled: $remindersEnabled, ')
          ..write('leadMinutes: $leadMinutes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    setId,
    title,
    teacher,
    location,
    colorOverrideHex,
    note,
    weekday,
    startPeriod,
    endPeriod,
    weeks,
    remindersEnabled,
    leadMinutes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseRule &&
          other.id == this.id &&
          other.setId == this.setId &&
          other.title == this.title &&
          other.teacher == this.teacher &&
          other.location == this.location &&
          other.colorOverrideHex == this.colorOverrideHex &&
          other.note == this.note &&
          other.weekday == this.weekday &&
          other.startPeriod == this.startPeriod &&
          other.endPeriod == this.endPeriod &&
          other.weeks == this.weeks &&
          other.remindersEnabled == this.remindersEnabled &&
          other.leadMinutes == this.leadMinutes);
}

class CourseRulesCompanion extends UpdateCompanion<CourseRule> {
  final Value<int> id;
  final Value<int> setId;
  final Value<String> title;
  final Value<String> teacher;
  final Value<String> location;
  final Value<String?> colorOverrideHex;
  final Value<String> note;
  final Value<int> weekday;
  final Value<int> startPeriod;
  final Value<int> endPeriod;
  final Value<List<int>> weeks;
  final Value<bool> remindersEnabled;
  final Value<int?> leadMinutes;
  const CourseRulesCompanion({
    this.id = const Value.absent(),
    this.setId = const Value.absent(),
    this.title = const Value.absent(),
    this.teacher = const Value.absent(),
    this.location = const Value.absent(),
    this.colorOverrideHex = const Value.absent(),
    this.note = const Value.absent(),
    this.weekday = const Value.absent(),
    this.startPeriod = const Value.absent(),
    this.endPeriod = const Value.absent(),
    this.weeks = const Value.absent(),
    this.remindersEnabled = const Value.absent(),
    this.leadMinutes = const Value.absent(),
  });
  CourseRulesCompanion.insert({
    this.id = const Value.absent(),
    required int setId,
    required String title,
    this.teacher = const Value.absent(),
    this.location = const Value.absent(),
    this.colorOverrideHex = const Value.absent(),
    this.note = const Value.absent(),
    required int weekday,
    required int startPeriod,
    required int endPeriod,
    required List<int> weeks,
    this.remindersEnabled = const Value.absent(),
    this.leadMinutes = const Value.absent(),
  }) : setId = Value(setId),
       title = Value(title),
       weekday = Value(weekday),
       startPeriod = Value(startPeriod),
       endPeriod = Value(endPeriod),
       weeks = Value(weeks);
  static Insertable<CourseRule> custom({
    Expression<int>? id,
    Expression<int>? setId,
    Expression<String>? title,
    Expression<String>? teacher,
    Expression<String>? location,
    Expression<String>? colorOverrideHex,
    Expression<String>? note,
    Expression<int>? weekday,
    Expression<int>? startPeriod,
    Expression<int>? endPeriod,
    Expression<String>? weeks,
    Expression<bool>? remindersEnabled,
    Expression<int>? leadMinutes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (setId != null) 'set_id': setId,
      if (title != null) 'title': title,
      if (teacher != null) 'teacher': teacher,
      if (location != null) 'location': location,
      if (colorOverrideHex != null) 'color_override_hex': colorOverrideHex,
      if (note != null) 'note': note,
      if (weekday != null) 'weekday': weekday,
      if (startPeriod != null) 'start_period': startPeriod,
      if (endPeriod != null) 'end_period': endPeriod,
      if (weeks != null) 'weeks': weeks,
      if (remindersEnabled != null) 'reminders_enabled': remindersEnabled,
      if (leadMinutes != null) 'lead_minutes': leadMinutes,
    });
  }

  CourseRulesCompanion copyWith({
    Value<int>? id,
    Value<int>? setId,
    Value<String>? title,
    Value<String>? teacher,
    Value<String>? location,
    Value<String?>? colorOverrideHex,
    Value<String>? note,
    Value<int>? weekday,
    Value<int>? startPeriod,
    Value<int>? endPeriod,
    Value<List<int>>? weeks,
    Value<bool>? remindersEnabled,
    Value<int?>? leadMinutes,
  }) {
    return CourseRulesCompanion(
      id: id ?? this.id,
      setId: setId ?? this.setId,
      title: title ?? this.title,
      teacher: teacher ?? this.teacher,
      location: location ?? this.location,
      colorOverrideHex: colorOverrideHex ?? this.colorOverrideHex,
      note: note ?? this.note,
      weekday: weekday ?? this.weekday,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      weeks: weeks ?? this.weeks,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      leadMinutes: leadMinutes ?? this.leadMinutes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (setId.present) {
      map['set_id'] = Variable<int>(setId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (teacher.present) {
      map['teacher'] = Variable<String>(teacher.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (colorOverrideHex.present) {
      map['color_override_hex'] = Variable<String>(colorOverrideHex.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (startPeriod.present) {
      map['start_period'] = Variable<int>(startPeriod.value);
    }
    if (endPeriod.present) {
      map['end_period'] = Variable<int>(endPeriod.value);
    }
    if (weeks.present) {
      map['weeks'] = Variable<String>(
        $CourseRulesTable.$converterweeks.toSql(weeks.value),
      );
    }
    if (remindersEnabled.present) {
      map['reminders_enabled'] = Variable<bool>(remindersEnabled.value);
    }
    if (leadMinutes.present) {
      map['lead_minutes'] = Variable<int>(leadMinutes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseRulesCompanion(')
          ..write('id: $id, ')
          ..write('setId: $setId, ')
          ..write('title: $title, ')
          ..write('teacher: $teacher, ')
          ..write('location: $location, ')
          ..write('colorOverrideHex: $colorOverrideHex, ')
          ..write('note: $note, ')
          ..write('weekday: $weekday, ')
          ..write('startPeriod: $startPeriod, ')
          ..write('endPeriod: $endPeriod, ')
          ..write('weeks: $weeks, ')
          ..write('remindersEnabled: $remindersEnabled, ')
          ..write('leadMinutes: $leadMinutes')
          ..write(')'))
        .toString();
  }
}

class $OneOffEventsTable extends OneOffEvents
    with TableInfo<$OneOffEventsTable, OneOffEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OneOffEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _setIdMeta = const VerificationMeta('setId');
  @override
  late final GeneratedColumn<int> setId = GeneratedColumn<int>(
    'set_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES calendar_sets (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorHexMeta = const VerificationMeta(
    'colorHex',
  );
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
    'color_hex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMinuteMeta = const VerificationMeta(
    'startMinute',
  );
  @override
  late final GeneratedColumn<int> startMinute = GeneratedColumn<int>(
    'start_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endMinuteMeta = const VerificationMeta(
    'endMinute',
  );
  @override
  late final GeneratedColumn<int> endMinute = GeneratedColumn<int>(
    'end_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    setId,
    title,
    location,
    note,
    colorHex,
    date,
    startMinute,
    endMinute,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'one_off_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<OneOffEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('set_id')) {
      context.handle(
        _setIdMeta,
        setId.isAcceptableOrUnknown(data['set_id']!, _setIdMeta),
      );
    } else if (isInserting) {
      context.missing(_setIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('color_hex')) {
      context.handle(
        _colorHexMeta,
        colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('start_minute')) {
      context.handle(
        _startMinuteMeta,
        startMinute.isAcceptableOrUnknown(
          data['start_minute']!,
          _startMinuteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startMinuteMeta);
    }
    if (data.containsKey('end_minute')) {
      context.handle(
        _endMinuteMeta,
        endMinute.isAcceptableOrUnknown(data['end_minute']!, _endMinuteMeta),
      );
    } else if (isInserting) {
      context.missing(_endMinuteMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OneOffEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OneOffEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      setId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}set_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      colorHex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_hex'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      startMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_minute'],
      )!,
      endMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_minute'],
      )!,
    );
  }

  @override
  $OneOffEventsTable createAlias(String alias) {
    return $OneOffEventsTable(attachedDatabase, alias);
  }
}

class OneOffEvent extends DataClass implements Insertable<OneOffEvent> {
  final int id;
  final int setId;
  final String title;
  final String location;
  final String note;
  final String? colorHex;
  final DateTime date;

  /// 距当日 00:00 的分钟数。与节次解耦 —— 单次事件不必落在整节上。
  final int startMinute;
  final int endMinute;
  const OneOffEvent({
    required this.id,
    required this.setId,
    required this.title,
    required this.location,
    required this.note,
    this.colorHex,
    required this.date,
    required this.startMinute,
    required this.endMinute,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['set_id'] = Variable<int>(setId);
    map['title'] = Variable<String>(title);
    map['location'] = Variable<String>(location);
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || colorHex != null) {
      map['color_hex'] = Variable<String>(colorHex);
    }
    map['date'] = Variable<DateTime>(date);
    map['start_minute'] = Variable<int>(startMinute);
    map['end_minute'] = Variable<int>(endMinute);
    return map;
  }

  OneOffEventsCompanion toCompanion(bool nullToAbsent) {
    return OneOffEventsCompanion(
      id: Value(id),
      setId: Value(setId),
      title: Value(title),
      location: Value(location),
      note: Value(note),
      colorHex: colorHex == null && nullToAbsent
          ? const Value.absent()
          : Value(colorHex),
      date: Value(date),
      startMinute: Value(startMinute),
      endMinute: Value(endMinute),
    );
  }

  factory OneOffEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OneOffEvent(
      id: serializer.fromJson<int>(json['id']),
      setId: serializer.fromJson<int>(json['setId']),
      title: serializer.fromJson<String>(json['title']),
      location: serializer.fromJson<String>(json['location']),
      note: serializer.fromJson<String>(json['note']),
      colorHex: serializer.fromJson<String?>(json['colorHex']),
      date: serializer.fromJson<DateTime>(json['date']),
      startMinute: serializer.fromJson<int>(json['startMinute']),
      endMinute: serializer.fromJson<int>(json['endMinute']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'setId': serializer.toJson<int>(setId),
      'title': serializer.toJson<String>(title),
      'location': serializer.toJson<String>(location),
      'note': serializer.toJson<String>(note),
      'colorHex': serializer.toJson<String?>(colorHex),
      'date': serializer.toJson<DateTime>(date),
      'startMinute': serializer.toJson<int>(startMinute),
      'endMinute': serializer.toJson<int>(endMinute),
    };
  }

  OneOffEvent copyWith({
    int? id,
    int? setId,
    String? title,
    String? location,
    String? note,
    Value<String?> colorHex = const Value.absent(),
    DateTime? date,
    int? startMinute,
    int? endMinute,
  }) => OneOffEvent(
    id: id ?? this.id,
    setId: setId ?? this.setId,
    title: title ?? this.title,
    location: location ?? this.location,
    note: note ?? this.note,
    colorHex: colorHex.present ? colorHex.value : this.colorHex,
    date: date ?? this.date,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
  );
  OneOffEvent copyWithCompanion(OneOffEventsCompanion data) {
    return OneOffEvent(
      id: data.id.present ? data.id.value : this.id,
      setId: data.setId.present ? data.setId.value : this.setId,
      title: data.title.present ? data.title.value : this.title,
      location: data.location.present ? data.location.value : this.location,
      note: data.note.present ? data.note.value : this.note,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      date: data.date.present ? data.date.value : this.date,
      startMinute: data.startMinute.present
          ? data.startMinute.value
          : this.startMinute,
      endMinute: data.endMinute.present ? data.endMinute.value : this.endMinute,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OneOffEvent(')
          ..write('id: $id, ')
          ..write('setId: $setId, ')
          ..write('title: $title, ')
          ..write('location: $location, ')
          ..write('note: $note, ')
          ..write('colorHex: $colorHex, ')
          ..write('date: $date, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    setId,
    title,
    location,
    note,
    colorHex,
    date,
    startMinute,
    endMinute,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OneOffEvent &&
          other.id == this.id &&
          other.setId == this.setId &&
          other.title == this.title &&
          other.location == this.location &&
          other.note == this.note &&
          other.colorHex == this.colorHex &&
          other.date == this.date &&
          other.startMinute == this.startMinute &&
          other.endMinute == this.endMinute);
}

class OneOffEventsCompanion extends UpdateCompanion<OneOffEvent> {
  final Value<int> id;
  final Value<int> setId;
  final Value<String> title;
  final Value<String> location;
  final Value<String> note;
  final Value<String?> colorHex;
  final Value<DateTime> date;
  final Value<int> startMinute;
  final Value<int> endMinute;
  const OneOffEventsCompanion({
    this.id = const Value.absent(),
    this.setId = const Value.absent(),
    this.title = const Value.absent(),
    this.location = const Value.absent(),
    this.note = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.date = const Value.absent(),
    this.startMinute = const Value.absent(),
    this.endMinute = const Value.absent(),
  });
  OneOffEventsCompanion.insert({
    this.id = const Value.absent(),
    required int setId,
    required String title,
    this.location = const Value.absent(),
    this.note = const Value.absent(),
    this.colorHex = const Value.absent(),
    required DateTime date,
    required int startMinute,
    required int endMinute,
  }) : setId = Value(setId),
       title = Value(title),
       date = Value(date),
       startMinute = Value(startMinute),
       endMinute = Value(endMinute);
  static Insertable<OneOffEvent> custom({
    Expression<int>? id,
    Expression<int>? setId,
    Expression<String>? title,
    Expression<String>? location,
    Expression<String>? note,
    Expression<String>? colorHex,
    Expression<DateTime>? date,
    Expression<int>? startMinute,
    Expression<int>? endMinute,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (setId != null) 'set_id': setId,
      if (title != null) 'title': title,
      if (location != null) 'location': location,
      if (note != null) 'note': note,
      if (colorHex != null) 'color_hex': colorHex,
      if (date != null) 'date': date,
      if (startMinute != null) 'start_minute': startMinute,
      if (endMinute != null) 'end_minute': endMinute,
    });
  }

  OneOffEventsCompanion copyWith({
    Value<int>? id,
    Value<int>? setId,
    Value<String>? title,
    Value<String>? location,
    Value<String>? note,
    Value<String?>? colorHex,
    Value<DateTime>? date,
    Value<int>? startMinute,
    Value<int>? endMinute,
  }) {
    return OneOffEventsCompanion(
      id: id ?? this.id,
      setId: setId ?? this.setId,
      title: title ?? this.title,
      location: location ?? this.location,
      note: note ?? this.note,
      colorHex: colorHex ?? this.colorHex,
      date: date ?? this.date,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (setId.present) {
      map['set_id'] = Variable<int>(setId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (startMinute.present) {
      map['start_minute'] = Variable<int>(startMinute.value);
    }
    if (endMinute.present) {
      map['end_minute'] = Variable<int>(endMinute.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OneOffEventsCompanion(')
          ..write('id: $id, ')
          ..write('setId: $setId, ')
          ..write('title: $title, ')
          ..write('location: $location, ')
          ..write('note: $note, ')
          ..write('colorHex: $colorHex, ')
          ..write('date: $date, ')
          ..write('startMinute: $startMinute, ')
          ..write('endMinute: $endMinute')
          ..write(')'))
        .toString();
  }
}

class $OccurrenceOverridesTable extends OccurrenceOverrides
    with TableInfo<$OccurrenceOverridesTable, OccurrenceOverride> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OccurrenceOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _ruleIdMeta = const VerificationMeta('ruleId');
  @override
  late final GeneratedColumn<int> ruleId = GeneratedColumn<int>(
    'rule_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES course_rules (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _originalDateMeta = const VerificationMeta(
    'originalDate',
  );
  @override
  late final GeneratedColumn<DateTime> originalDate = GeneratedColumn<DateTime>(
    'original_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cancelledMeta = const VerificationMeta(
    'cancelled',
  );
  @override
  late final GeneratedColumn<bool> cancelled = GeneratedColumn<bool>(
    'cancelled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("cancelled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _newDateMeta = const VerificationMeta(
    'newDate',
  );
  @override
  late final GeneratedColumn<DateTime> newDate = GeneratedColumn<DateTime>(
    'new_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _newStartMinuteMeta = const VerificationMeta(
    'newStartMinute',
  );
  @override
  late final GeneratedColumn<int> newStartMinute = GeneratedColumn<int>(
    'new_start_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _newEndMinuteMeta = const VerificationMeta(
    'newEndMinute',
  );
  @override
  late final GeneratedColumn<int> newEndMinute = GeneratedColumn<int>(
    'new_end_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _newLocationMeta = const VerificationMeta(
    'newLocation',
  );
  @override
  late final GeneratedColumn<String> newLocation = GeneratedColumn<String>(
    'new_location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _newTitleMeta = const VerificationMeta(
    'newTitle',
  );
  @override
  late final GeneratedColumn<String> newTitle = GeneratedColumn<String>(
    'new_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ruleId,
    originalDate,
    cancelled,
    newDate,
    newStartMinute,
    newEndMinute,
    newLocation,
    newTitle,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'occurrence_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<OccurrenceOverride> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('rule_id')) {
      context.handle(
        _ruleIdMeta,
        ruleId.isAcceptableOrUnknown(data['rule_id']!, _ruleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleIdMeta);
    }
    if (data.containsKey('original_date')) {
      context.handle(
        _originalDateMeta,
        originalDate.isAcceptableOrUnknown(
          data['original_date']!,
          _originalDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalDateMeta);
    }
    if (data.containsKey('cancelled')) {
      context.handle(
        _cancelledMeta,
        cancelled.isAcceptableOrUnknown(data['cancelled']!, _cancelledMeta),
      );
    }
    if (data.containsKey('new_date')) {
      context.handle(
        _newDateMeta,
        newDate.isAcceptableOrUnknown(data['new_date']!, _newDateMeta),
      );
    }
    if (data.containsKey('new_start_minute')) {
      context.handle(
        _newStartMinuteMeta,
        newStartMinute.isAcceptableOrUnknown(
          data['new_start_minute']!,
          _newStartMinuteMeta,
        ),
      );
    }
    if (data.containsKey('new_end_minute')) {
      context.handle(
        _newEndMinuteMeta,
        newEndMinute.isAcceptableOrUnknown(
          data['new_end_minute']!,
          _newEndMinuteMeta,
        ),
      );
    }
    if (data.containsKey('new_location')) {
      context.handle(
        _newLocationMeta,
        newLocation.isAcceptableOrUnknown(
          data['new_location']!,
          _newLocationMeta,
        ),
      );
    }
    if (data.containsKey('new_title')) {
      context.handle(
        _newTitleMeta,
        newTitle.isAcceptableOrUnknown(data['new_title']!, _newTitleMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OccurrenceOverride map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OccurrenceOverride(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      ruleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rule_id'],
      )!,
      originalDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}original_date'],
      )!,
      cancelled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}cancelled'],
      )!,
      newDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}new_date'],
      ),
      newStartMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}new_start_minute'],
      ),
      newEndMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}new_end_minute'],
      ),
      newLocation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}new_location'],
      ),
      newTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}new_title'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OccurrenceOverridesTable createAlias(String alias) {
    return $OccurrenceOverridesTable(attachedDatabase, alias);
  }
}

class OccurrenceOverride extends DataClass
    implements Insertable<OccurrenceOverride> {
  final int id;
  final int ruleId;

  /// 被覆盖的那一次原本的日期（未经平移的原始日期）。
  final DateTime originalDate;

  /// 这一次停课。
  final bool cancelled;
  final DateTime? newDate;
  final int? newStartMinute;
  final int? newEndMinute;
  final String? newLocation;
  final String? newTitle;
  final DateTime createdAt;
  const OccurrenceOverride({
    required this.id,
    required this.ruleId,
    required this.originalDate,
    required this.cancelled,
    this.newDate,
    this.newStartMinute,
    this.newEndMinute,
    this.newLocation,
    this.newTitle,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['rule_id'] = Variable<int>(ruleId);
    map['original_date'] = Variable<DateTime>(originalDate);
    map['cancelled'] = Variable<bool>(cancelled);
    if (!nullToAbsent || newDate != null) {
      map['new_date'] = Variable<DateTime>(newDate);
    }
    if (!nullToAbsent || newStartMinute != null) {
      map['new_start_minute'] = Variable<int>(newStartMinute);
    }
    if (!nullToAbsent || newEndMinute != null) {
      map['new_end_minute'] = Variable<int>(newEndMinute);
    }
    if (!nullToAbsent || newLocation != null) {
      map['new_location'] = Variable<String>(newLocation);
    }
    if (!nullToAbsent || newTitle != null) {
      map['new_title'] = Variable<String>(newTitle);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OccurrenceOverridesCompanion toCompanion(bool nullToAbsent) {
    return OccurrenceOverridesCompanion(
      id: Value(id),
      ruleId: Value(ruleId),
      originalDate: Value(originalDate),
      cancelled: Value(cancelled),
      newDate: newDate == null && nullToAbsent
          ? const Value.absent()
          : Value(newDate),
      newStartMinute: newStartMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(newStartMinute),
      newEndMinute: newEndMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(newEndMinute),
      newLocation: newLocation == null && nullToAbsent
          ? const Value.absent()
          : Value(newLocation),
      newTitle: newTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(newTitle),
      createdAt: Value(createdAt),
    );
  }

  factory OccurrenceOverride.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OccurrenceOverride(
      id: serializer.fromJson<int>(json['id']),
      ruleId: serializer.fromJson<int>(json['ruleId']),
      originalDate: serializer.fromJson<DateTime>(json['originalDate']),
      cancelled: serializer.fromJson<bool>(json['cancelled']),
      newDate: serializer.fromJson<DateTime?>(json['newDate']),
      newStartMinute: serializer.fromJson<int?>(json['newStartMinute']),
      newEndMinute: serializer.fromJson<int?>(json['newEndMinute']),
      newLocation: serializer.fromJson<String?>(json['newLocation']),
      newTitle: serializer.fromJson<String?>(json['newTitle']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ruleId': serializer.toJson<int>(ruleId),
      'originalDate': serializer.toJson<DateTime>(originalDate),
      'cancelled': serializer.toJson<bool>(cancelled),
      'newDate': serializer.toJson<DateTime?>(newDate),
      'newStartMinute': serializer.toJson<int?>(newStartMinute),
      'newEndMinute': serializer.toJson<int?>(newEndMinute),
      'newLocation': serializer.toJson<String?>(newLocation),
      'newTitle': serializer.toJson<String?>(newTitle),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OccurrenceOverride copyWith({
    int? id,
    int? ruleId,
    DateTime? originalDate,
    bool? cancelled,
    Value<DateTime?> newDate = const Value.absent(),
    Value<int?> newStartMinute = const Value.absent(),
    Value<int?> newEndMinute = const Value.absent(),
    Value<String?> newLocation = const Value.absent(),
    Value<String?> newTitle = const Value.absent(),
    DateTime? createdAt,
  }) => OccurrenceOverride(
    id: id ?? this.id,
    ruleId: ruleId ?? this.ruleId,
    originalDate: originalDate ?? this.originalDate,
    cancelled: cancelled ?? this.cancelled,
    newDate: newDate.present ? newDate.value : this.newDate,
    newStartMinute: newStartMinute.present
        ? newStartMinute.value
        : this.newStartMinute,
    newEndMinute: newEndMinute.present ? newEndMinute.value : this.newEndMinute,
    newLocation: newLocation.present ? newLocation.value : this.newLocation,
    newTitle: newTitle.present ? newTitle.value : this.newTitle,
    createdAt: createdAt ?? this.createdAt,
  );
  OccurrenceOverride copyWithCompanion(OccurrenceOverridesCompanion data) {
    return OccurrenceOverride(
      id: data.id.present ? data.id.value : this.id,
      ruleId: data.ruleId.present ? data.ruleId.value : this.ruleId,
      originalDate: data.originalDate.present
          ? data.originalDate.value
          : this.originalDate,
      cancelled: data.cancelled.present ? data.cancelled.value : this.cancelled,
      newDate: data.newDate.present ? data.newDate.value : this.newDate,
      newStartMinute: data.newStartMinute.present
          ? data.newStartMinute.value
          : this.newStartMinute,
      newEndMinute: data.newEndMinute.present
          ? data.newEndMinute.value
          : this.newEndMinute,
      newLocation: data.newLocation.present
          ? data.newLocation.value
          : this.newLocation,
      newTitle: data.newTitle.present ? data.newTitle.value : this.newTitle,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OccurrenceOverride(')
          ..write('id: $id, ')
          ..write('ruleId: $ruleId, ')
          ..write('originalDate: $originalDate, ')
          ..write('cancelled: $cancelled, ')
          ..write('newDate: $newDate, ')
          ..write('newStartMinute: $newStartMinute, ')
          ..write('newEndMinute: $newEndMinute, ')
          ..write('newLocation: $newLocation, ')
          ..write('newTitle: $newTitle, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ruleId,
    originalDate,
    cancelled,
    newDate,
    newStartMinute,
    newEndMinute,
    newLocation,
    newTitle,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OccurrenceOverride &&
          other.id == this.id &&
          other.ruleId == this.ruleId &&
          other.originalDate == this.originalDate &&
          other.cancelled == this.cancelled &&
          other.newDate == this.newDate &&
          other.newStartMinute == this.newStartMinute &&
          other.newEndMinute == this.newEndMinute &&
          other.newLocation == this.newLocation &&
          other.newTitle == this.newTitle &&
          other.createdAt == this.createdAt);
}

class OccurrenceOverridesCompanion extends UpdateCompanion<OccurrenceOverride> {
  final Value<int> id;
  final Value<int> ruleId;
  final Value<DateTime> originalDate;
  final Value<bool> cancelled;
  final Value<DateTime?> newDate;
  final Value<int?> newStartMinute;
  final Value<int?> newEndMinute;
  final Value<String?> newLocation;
  final Value<String?> newTitle;
  final Value<DateTime> createdAt;
  const OccurrenceOverridesCompanion({
    this.id = const Value.absent(),
    this.ruleId = const Value.absent(),
    this.originalDate = const Value.absent(),
    this.cancelled = const Value.absent(),
    this.newDate = const Value.absent(),
    this.newStartMinute = const Value.absent(),
    this.newEndMinute = const Value.absent(),
    this.newLocation = const Value.absent(),
    this.newTitle = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OccurrenceOverridesCompanion.insert({
    this.id = const Value.absent(),
    required int ruleId,
    required DateTime originalDate,
    this.cancelled = const Value.absent(),
    this.newDate = const Value.absent(),
    this.newStartMinute = const Value.absent(),
    this.newEndMinute = const Value.absent(),
    this.newLocation = const Value.absent(),
    this.newTitle = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : ruleId = Value(ruleId),
       originalDate = Value(originalDate);
  static Insertable<OccurrenceOverride> custom({
    Expression<int>? id,
    Expression<int>? ruleId,
    Expression<DateTime>? originalDate,
    Expression<bool>? cancelled,
    Expression<DateTime>? newDate,
    Expression<int>? newStartMinute,
    Expression<int>? newEndMinute,
    Expression<String>? newLocation,
    Expression<String>? newTitle,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ruleId != null) 'rule_id': ruleId,
      if (originalDate != null) 'original_date': originalDate,
      if (cancelled != null) 'cancelled': cancelled,
      if (newDate != null) 'new_date': newDate,
      if (newStartMinute != null) 'new_start_minute': newStartMinute,
      if (newEndMinute != null) 'new_end_minute': newEndMinute,
      if (newLocation != null) 'new_location': newLocation,
      if (newTitle != null) 'new_title': newTitle,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OccurrenceOverridesCompanion copyWith({
    Value<int>? id,
    Value<int>? ruleId,
    Value<DateTime>? originalDate,
    Value<bool>? cancelled,
    Value<DateTime?>? newDate,
    Value<int?>? newStartMinute,
    Value<int?>? newEndMinute,
    Value<String?>? newLocation,
    Value<String?>? newTitle,
    Value<DateTime>? createdAt,
  }) {
    return OccurrenceOverridesCompanion(
      id: id ?? this.id,
      ruleId: ruleId ?? this.ruleId,
      originalDate: originalDate ?? this.originalDate,
      cancelled: cancelled ?? this.cancelled,
      newDate: newDate ?? this.newDate,
      newStartMinute: newStartMinute ?? this.newStartMinute,
      newEndMinute: newEndMinute ?? this.newEndMinute,
      newLocation: newLocation ?? this.newLocation,
      newTitle: newTitle ?? this.newTitle,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ruleId.present) {
      map['rule_id'] = Variable<int>(ruleId.value);
    }
    if (originalDate.present) {
      map['original_date'] = Variable<DateTime>(originalDate.value);
    }
    if (cancelled.present) {
      map['cancelled'] = Variable<bool>(cancelled.value);
    }
    if (newDate.present) {
      map['new_date'] = Variable<DateTime>(newDate.value);
    }
    if (newStartMinute.present) {
      map['new_start_minute'] = Variable<int>(newStartMinute.value);
    }
    if (newEndMinute.present) {
      map['new_end_minute'] = Variable<int>(newEndMinute.value);
    }
    if (newLocation.present) {
      map['new_location'] = Variable<String>(newLocation.value);
    }
    if (newTitle.present) {
      map['new_title'] = Variable<String>(newTitle.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OccurrenceOverridesCompanion(')
          ..write('id: $id, ')
          ..write('ruleId: $ruleId, ')
          ..write('originalDate: $originalDate, ')
          ..write('cancelled: $cancelled, ')
          ..write('newDate: $newDate, ')
          ..write('newStartMinute: $newStartMinute, ')
          ..write('newEndMinute: $newEndMinute, ')
          ..write('newLocation: $newLocation, ')
          ..write('newTitle: $newTitle, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CalendarSetsTable calendarSets = $CalendarSetsTable(this);
  late final $CourseRulesTable courseRules = $CourseRulesTable(this);
  late final $OneOffEventsTable oneOffEvents = $OneOffEventsTable(this);
  late final $OccurrenceOverridesTable occurrenceOverrides =
      $OccurrenceOverridesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    calendarSets,
    courseRules,
    oneOffEvents,
    occurrenceOverrides,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'calendar_sets',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('course_rules', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'calendar_sets',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('one_off_events', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'course_rules',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('occurrence_overrides', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$CalendarSetsTableCreateCompanionBuilder =
    CalendarSetsCompanion Function({
      Value<int> id,
      required String name,
      Value<String> colorSeedHex,
      Value<int> tabOrder,
      required DateTime week1Monday,
      Value<bool> visible,
      Value<int> weekShift,
      Value<int> timeShiftMinutes,
      Value<String?> sourceName,
      Value<DateTime> createdAt,
    });
typedef $$CalendarSetsTableUpdateCompanionBuilder =
    CalendarSetsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> colorSeedHex,
      Value<int> tabOrder,
      Value<DateTime> week1Monday,
      Value<bool> visible,
      Value<int> weekShift,
      Value<int> timeShiftMinutes,
      Value<String?> sourceName,
      Value<DateTime> createdAt,
    });

final class $$CalendarSetsTableReferences
    extends BaseReferences<_$AppDatabase, $CalendarSetsTable, CalendarSet> {
  $$CalendarSetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CourseRulesTable, List<CourseRule>>
  _courseRulesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.courseRules,
    aliasName: 'calendar_sets__id__course_rules__set_id',
  );

  $$CourseRulesTableProcessedTableManager get courseRulesRefs {
    final manager = $$CourseRulesTableTableManager(
      $_db,
      $_db.courseRules,
    ).filter((f) => f.setId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_courseRulesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OneOffEventsTable, List<OneOffEvent>>
  _oneOffEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.oneOffEvents,
    aliasName: 'calendar_sets__id__one_off_events__set_id',
  );

  $$OneOffEventsTableProcessedTableManager get oneOffEventsRefs {
    final manager = $$OneOffEventsTableTableManager(
      $_db,
      $_db.oneOffEvents,
    ).filter((f) => f.setId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_oneOffEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CalendarSetsTableFilterComposer
    extends Composer<_$AppDatabase, $CalendarSetsTable> {
  $$CalendarSetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorSeedHex => $composableBuilder(
    column: $table.colorSeedHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tabOrder => $composableBuilder(
    column: $table.tabOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get week1Monday => $composableBuilder(
    column: $table.week1Monday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get visible => $composableBuilder(
    column: $table.visible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekShift => $composableBuilder(
    column: $table.weekShift,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeShiftMinutes => $composableBuilder(
    column: $table.timeShiftMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> courseRulesRefs(
    Expression<bool> Function($$CourseRulesTableFilterComposer f) f,
  ) {
    final $$CourseRulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.courseRules,
      getReferencedColumn: (t) => t.setId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRulesTableFilterComposer(
            $db: $db,
            $table: $db.courseRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> oneOffEventsRefs(
    Expression<bool> Function($$OneOffEventsTableFilterComposer f) f,
  ) {
    final $$OneOffEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.oneOffEvents,
      getReferencedColumn: (t) => t.setId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OneOffEventsTableFilterComposer(
            $db: $db,
            $table: $db.oneOffEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CalendarSetsTableOrderingComposer
    extends Composer<_$AppDatabase, $CalendarSetsTable> {
  $$CalendarSetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorSeedHex => $composableBuilder(
    column: $table.colorSeedHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tabOrder => $composableBuilder(
    column: $table.tabOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get week1Monday => $composableBuilder(
    column: $table.week1Monday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get visible => $composableBuilder(
    column: $table.visible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekShift => $composableBuilder(
    column: $table.weekShift,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeShiftMinutes => $composableBuilder(
    column: $table.timeShiftMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CalendarSetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalendarSetsTable> {
  $$CalendarSetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorSeedHex => $composableBuilder(
    column: $table.colorSeedHex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tabOrder =>
      $composableBuilder(column: $table.tabOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get week1Monday => $composableBuilder(
    column: $table.week1Monday,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get visible =>
      $composableBuilder(column: $table.visible, builder: (column) => column);

  GeneratedColumn<int> get weekShift =>
      $composableBuilder(column: $table.weekShift, builder: (column) => column);

  GeneratedColumn<int> get timeShiftMinutes => $composableBuilder(
    column: $table.timeShiftMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> courseRulesRefs<T extends Object>(
    Expression<T> Function($$CourseRulesTableAnnotationComposer a) f,
  ) {
    final $$CourseRulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.courseRules,
      getReferencedColumn: (t) => t.setId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRulesTableAnnotationComposer(
            $db: $db,
            $table: $db.courseRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> oneOffEventsRefs<T extends Object>(
    Expression<T> Function($$OneOffEventsTableAnnotationComposer a) f,
  ) {
    final $$OneOffEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.oneOffEvents,
      getReferencedColumn: (t) => t.setId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OneOffEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.oneOffEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CalendarSetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CalendarSetsTable,
          CalendarSet,
          $$CalendarSetsTableFilterComposer,
          $$CalendarSetsTableOrderingComposer,
          $$CalendarSetsTableAnnotationComposer,
          $$CalendarSetsTableCreateCompanionBuilder,
          $$CalendarSetsTableUpdateCompanionBuilder,
          (CalendarSet, $$CalendarSetsTableReferences),
          CalendarSet,
          PrefetchHooks Function({bool courseRulesRefs, bool oneOffEventsRefs})
        > {
  $$CalendarSetsTableTableManager(_$AppDatabase db, $CalendarSetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalendarSetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalendarSetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalendarSetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> colorSeedHex = const Value.absent(),
                Value<int> tabOrder = const Value.absent(),
                Value<DateTime> week1Monday = const Value.absent(),
                Value<bool> visible = const Value.absent(),
                Value<int> weekShift = const Value.absent(),
                Value<int> timeShiftMinutes = const Value.absent(),
                Value<String?> sourceName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => CalendarSetsCompanion(
                id: id,
                name: name,
                colorSeedHex: colorSeedHex,
                tabOrder: tabOrder,
                week1Monday: week1Monday,
                visible: visible,
                weekShift: weekShift,
                timeShiftMinutes: timeShiftMinutes,
                sourceName: sourceName,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> colorSeedHex = const Value.absent(),
                Value<int> tabOrder = const Value.absent(),
                required DateTime week1Monday,
                Value<bool> visible = const Value.absent(),
                Value<int> weekShift = const Value.absent(),
                Value<int> timeShiftMinutes = const Value.absent(),
                Value<String?> sourceName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => CalendarSetsCompanion.insert(
                id: id,
                name: name,
                colorSeedHex: colorSeedHex,
                tabOrder: tabOrder,
                week1Monday: week1Monday,
                visible: visible,
                weekShift: weekShift,
                timeShiftMinutes: timeShiftMinutes,
                sourceName: sourceName,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CalendarSetsTable, CalendarSet>(table),
                  $$CalendarSetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({courseRulesRefs = false, oneOffEventsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (courseRulesRefs) db.courseRules,
                    if (oneOffEventsRefs) db.oneOffEvents,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (courseRulesRefs)
                        await $_getPrefetchedData<
                          CalendarSet,
                          $CalendarSetsTable,
                          CourseRule
                        >(
                          currentTable: table,
                          referencedTable: $$CalendarSetsTableReferences
                              ._courseRulesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CalendarSetsTableReferences(
                                db,
                                table,
                                p0,
                              ).courseRulesRefs,
                          referencedItemsForCurrentItem: (
                            item,
                            referencedItems,
                          ) => referencedItems.where((e) => e.setId == item.id),
                          typedResults: items,
                        ),
                      if (oneOffEventsRefs)
                        await $_getPrefetchedData<
                          CalendarSet,
                          $CalendarSetsTable,
                          OneOffEvent
                        >(
                          currentTable: table,
                          referencedTable: $$CalendarSetsTableReferences
                              ._oneOffEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CalendarSetsTableReferences(
                                db,
                                table,
                                p0,
                              ).oneOffEventsRefs,
                          referencedItemsForCurrentItem: (
                            item,
                            referencedItems,
                          ) => referencedItems.where((e) => e.setId == item.id),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CalendarSetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CalendarSetsTable,
      CalendarSet,
      $$CalendarSetsTableFilterComposer,
      $$CalendarSetsTableOrderingComposer,
      $$CalendarSetsTableAnnotationComposer,
      $$CalendarSetsTableCreateCompanionBuilder,
      $$CalendarSetsTableUpdateCompanionBuilder,
      (CalendarSet, $$CalendarSetsTableReferences),
      CalendarSet,
      PrefetchHooks Function({bool courseRulesRefs, bool oneOffEventsRefs})
    >;
typedef $$CourseRulesTableCreateCompanionBuilder =
    CourseRulesCompanion Function({
      Value<int> id,
      required int setId,
      required String title,
      Value<String> teacher,
      Value<String> location,
      Value<String?> colorOverrideHex,
      Value<String> note,
      required int weekday,
      required int startPeriod,
      required int endPeriod,
      required List<int> weeks,
      Value<bool> remindersEnabled,
      Value<int?> leadMinutes,
    });
typedef $$CourseRulesTableUpdateCompanionBuilder =
    CourseRulesCompanion Function({
      Value<int> id,
      Value<int> setId,
      Value<String> title,
      Value<String> teacher,
      Value<String> location,
      Value<String?> colorOverrideHex,
      Value<String> note,
      Value<int> weekday,
      Value<int> startPeriod,
      Value<int> endPeriod,
      Value<List<int>> weeks,
      Value<bool> remindersEnabled,
      Value<int?> leadMinutes,
    });

final class $$CourseRulesTableReferences
    extends BaseReferences<_$AppDatabase, $CourseRulesTable, CourseRule> {
  $$CourseRulesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CalendarSetsTable _setIdTable(_$AppDatabase db) =>
      db.calendarSets.createAlias('course_rules__set_id__calendar_sets__id');

  $$CalendarSetsTableProcessedTableManager get setId {
    final $_column = $_itemColumn<int>('set_id')!;

    final manager = $$CalendarSetsTableTableManager(
      $_db,
      $_db.calendarSets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_setIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $OccurrenceOverridesTable,
    List<OccurrenceOverride>
  >
  _occurrenceOverridesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.occurrenceOverrides,
        aliasName: 'course_rules__id__occurrence_overrides__rule_id',
      );

  $$OccurrenceOverridesTableProcessedTableManager get occurrenceOverridesRefs {
    final manager = $$OccurrenceOverridesTableTableManager(
      $_db,
      $_db.occurrenceOverrides,
    ).filter((f) => f.ruleId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _occurrenceOverridesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CourseRulesTableFilterComposer
    extends Composer<_$AppDatabase, $CourseRulesTable> {
  $$CourseRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teacher => $composableBuilder(
    column: $table.teacher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorOverrideHex => $composableBuilder(
    column: $table.colorOverrideHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startPeriod => $composableBuilder(
    column: $table.startPeriod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endPeriod => $composableBuilder(
    column: $table.endPeriod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<int>, List<int>, String> get weeks =>
      $composableBuilder(
        column: $table.weeks,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get remindersEnabled => $composableBuilder(
    column: $table.remindersEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get leadMinutes => $composableBuilder(
    column: $table.leadMinutes,
    builder: (column) => ColumnFilters(column),
  );

  $$CalendarSetsTableFilterComposer get setId {
    final $$CalendarSetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.calendarSets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarSetsTableFilterComposer(
            $db: $db,
            $table: $db.calendarSets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> occurrenceOverridesRefs(
    Expression<bool> Function($$OccurrenceOverridesTableFilterComposer f) f,
  ) {
    final $$OccurrenceOverridesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.occurrenceOverrides,
      getReferencedColumn: (t) => t.ruleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OccurrenceOverridesTableFilterComposer(
            $db: $db,
            $table: $db.occurrenceOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CourseRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $CourseRulesTable> {
  $$CourseRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teacher => $composableBuilder(
    column: $table.teacher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorOverrideHex => $composableBuilder(
    column: $table.colorOverrideHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startPeriod => $composableBuilder(
    column: $table.startPeriod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endPeriod => $composableBuilder(
    column: $table.endPeriod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weeks => $composableBuilder(
    column: $table.weeks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get remindersEnabled => $composableBuilder(
    column: $table.remindersEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get leadMinutes => $composableBuilder(
    column: $table.leadMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  $$CalendarSetsTableOrderingComposer get setId {
    final $$CalendarSetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.calendarSets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarSetsTableOrderingComposer(
            $db: $db,
            $table: $db.calendarSets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CourseRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourseRulesTable> {
  $$CourseRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get teacher =>
      $composableBuilder(column: $table.teacher, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get colorOverrideHex => $composableBuilder(
    column: $table.colorOverrideHex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<int> get startPeriod => $composableBuilder(
    column: $table.startPeriod,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endPeriod =>
      $composableBuilder(column: $table.endPeriod, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<int>, String> get weeks =>
      $composableBuilder(column: $table.weeks, builder: (column) => column);

  GeneratedColumn<bool> get remindersEnabled => $composableBuilder(
    column: $table.remindersEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get leadMinutes => $composableBuilder(
    column: $table.leadMinutes,
    builder: (column) => column,
  );

  $$CalendarSetsTableAnnotationComposer get setId {
    final $$CalendarSetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.calendarSets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarSetsTableAnnotationComposer(
            $db: $db,
            $table: $db.calendarSets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> occurrenceOverridesRefs<T extends Object>(
    Expression<T> Function($$OccurrenceOverridesTableAnnotationComposer a) f,
  ) {
    final $$OccurrenceOverridesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.occurrenceOverrides,
          getReferencedColumn: (t) => t.ruleId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OccurrenceOverridesTableAnnotationComposer(
                $db: $db,
                $table: $db.occurrenceOverrides,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CourseRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CourseRulesTable,
          CourseRule,
          $$CourseRulesTableFilterComposer,
          $$CourseRulesTableOrderingComposer,
          $$CourseRulesTableAnnotationComposer,
          $$CourseRulesTableCreateCompanionBuilder,
          $$CourseRulesTableUpdateCompanionBuilder,
          (CourseRule, $$CourseRulesTableReferences),
          CourseRule,
          PrefetchHooks Function({bool setId, bool occurrenceOverridesRefs})
        > {
  $$CourseRulesTableTableManager(_$AppDatabase db, $CourseRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourseRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourseRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> setId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> teacher = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<String?> colorOverrideHex = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<int> startPeriod = const Value.absent(),
                Value<int> endPeriod = const Value.absent(),
                Value<List<int>> weeks = const Value.absent(),
                Value<bool> remindersEnabled = const Value.absent(),
                Value<int?> leadMinutes = const Value.absent(),
              }) => CourseRulesCompanion(
                id: id,
                setId: setId,
                title: title,
                teacher: teacher,
                location: location,
                colorOverrideHex: colorOverrideHex,
                note: note,
                weekday: weekday,
                startPeriod: startPeriod,
                endPeriod: endPeriod,
                weeks: weeks,
                remindersEnabled: remindersEnabled,
                leadMinutes: leadMinutes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int setId,
                required String title,
                Value<String> teacher = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<String?> colorOverrideHex = const Value.absent(),
                Value<String> note = const Value.absent(),
                required int weekday,
                required int startPeriod,
                required int endPeriod,
                required List<int> weeks,
                Value<bool> remindersEnabled = const Value.absent(),
                Value<int?> leadMinutes = const Value.absent(),
              }) => CourseRulesCompanion.insert(
                id: id,
                setId: setId,
                title: title,
                teacher: teacher,
                location: location,
                colorOverrideHex: colorOverrideHex,
                note: note,
                weekday: weekday,
                startPeriod: startPeriod,
                endPeriod: endPeriod,
                weeks: weeks,
                remindersEnabled: remindersEnabled,
                leadMinutes: leadMinutes,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CourseRulesTable, CourseRule>(table),
                  $$CourseRulesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({setId = false, occurrenceOverridesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (occurrenceOverridesRefs) db.occurrenceOverrides,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (setId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.setId,
                            referencedTable: $$CourseRulesTableReferences
                                ._setIdTable(db),
                            referencedColumn: $$CourseRulesTableReferences
                                ._setIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (occurrenceOverridesRefs)
                        await $_getPrefetchedData<
                          CourseRule,
                          $CourseRulesTable,
                          OccurrenceOverride
                        >(
                          currentTable: table,
                          referencedTable: $$CourseRulesTableReferences
                              ._occurrenceOverridesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CourseRulesTableReferences(
                                db,
                                table,
                                p0,
                              ).occurrenceOverridesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ruleId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CourseRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CourseRulesTable,
      CourseRule,
      $$CourseRulesTableFilterComposer,
      $$CourseRulesTableOrderingComposer,
      $$CourseRulesTableAnnotationComposer,
      $$CourseRulesTableCreateCompanionBuilder,
      $$CourseRulesTableUpdateCompanionBuilder,
      (CourseRule, $$CourseRulesTableReferences),
      CourseRule,
      PrefetchHooks Function({bool setId, bool occurrenceOverridesRefs})
    >;
typedef $$OneOffEventsTableCreateCompanionBuilder =
    OneOffEventsCompanion Function({
      Value<int> id,
      required int setId,
      required String title,
      Value<String> location,
      Value<String> note,
      Value<String?> colorHex,
      required DateTime date,
      required int startMinute,
      required int endMinute,
    });
typedef $$OneOffEventsTableUpdateCompanionBuilder =
    OneOffEventsCompanion Function({
      Value<int> id,
      Value<int> setId,
      Value<String> title,
      Value<String> location,
      Value<String> note,
      Value<String?> colorHex,
      Value<DateTime> date,
      Value<int> startMinute,
      Value<int> endMinute,
    });

final class $$OneOffEventsTableReferences
    extends BaseReferences<_$AppDatabase, $OneOffEventsTable, OneOffEvent> {
  $$OneOffEventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CalendarSetsTable _setIdTable(_$AppDatabase db) =>
      db.calendarSets.createAlias('one_off_events__set_id__calendar_sets__id');

  $$CalendarSetsTableProcessedTableManager get setId {
    final $_column = $_itemColumn<int>('set_id')!;

    final manager = $$CalendarSetsTableTableManager(
      $_db,
      $_db.calendarSets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_setIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OneOffEventsTableFilterComposer
    extends Composer<_$AppDatabase, $OneOffEventsTable> {
  $$OneOffEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnFilters(column),
  );

  $$CalendarSetsTableFilterComposer get setId {
    final $$CalendarSetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.calendarSets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarSetsTableFilterComposer(
            $db: $db,
            $table: $db.calendarSets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OneOffEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $OneOffEventsTable> {
  $$OneOffEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorHex => $composableBuilder(
    column: $table.colorHex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endMinute => $composableBuilder(
    column: $table.endMinute,
    builder: (column) => ColumnOrderings(column),
  );

  $$CalendarSetsTableOrderingComposer get setId {
    final $$CalendarSetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.calendarSets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarSetsTableOrderingComposer(
            $db: $db,
            $table: $db.calendarSets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OneOffEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OneOffEventsTable> {
  $$OneOffEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get colorHex =>
      $composableBuilder(column: $table.colorHex, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get startMinute => $composableBuilder(
    column: $table.startMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endMinute =>
      $composableBuilder(column: $table.endMinute, builder: (column) => column);

  $$CalendarSetsTableAnnotationComposer get setId {
    final $$CalendarSetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.calendarSets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CalendarSetsTableAnnotationComposer(
            $db: $db,
            $table: $db.calendarSets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OneOffEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OneOffEventsTable,
          OneOffEvent,
          $$OneOffEventsTableFilterComposer,
          $$OneOffEventsTableOrderingComposer,
          $$OneOffEventsTableAnnotationComposer,
          $$OneOffEventsTableCreateCompanionBuilder,
          $$OneOffEventsTableUpdateCompanionBuilder,
          (OneOffEvent, $$OneOffEventsTableReferences),
          OneOffEvent,
          PrefetchHooks Function({bool setId})
        > {
  $$OneOffEventsTableTableManager(_$AppDatabase db, $OneOffEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OneOffEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OneOffEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OneOffEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> setId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> location = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> colorHex = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<int> startMinute = const Value.absent(),
                Value<int> endMinute = const Value.absent(),
              }) => OneOffEventsCompanion(
                id: id,
                setId: setId,
                title: title,
                location: location,
                note: note,
                colorHex: colorHex,
                date: date,
                startMinute: startMinute,
                endMinute: endMinute,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int setId,
                required String title,
                Value<String> location = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> colorHex = const Value.absent(),
                required DateTime date,
                required int startMinute,
                required int endMinute,
              }) => OneOffEventsCompanion.insert(
                id: id,
                setId: setId,
                title: title,
                location: location,
                note: note,
                colorHex: colorHex,
                date: date,
                startMinute: startMinute,
                endMinute: endMinute,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OneOffEventsTable, OneOffEvent>(table),
                  $$OneOffEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({setId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (setId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.setId,
                        referencedTable: $$OneOffEventsTableReferences
                            ._setIdTable(db),
                        referencedColumn: $$OneOffEventsTableReferences
                            ._setIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OneOffEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OneOffEventsTable,
      OneOffEvent,
      $$OneOffEventsTableFilterComposer,
      $$OneOffEventsTableOrderingComposer,
      $$OneOffEventsTableAnnotationComposer,
      $$OneOffEventsTableCreateCompanionBuilder,
      $$OneOffEventsTableUpdateCompanionBuilder,
      (OneOffEvent, $$OneOffEventsTableReferences),
      OneOffEvent,
      PrefetchHooks Function({bool setId})
    >;
typedef $$OccurrenceOverridesTableCreateCompanionBuilder =
    OccurrenceOverridesCompanion Function({
      Value<int> id,
      required int ruleId,
      required DateTime originalDate,
      Value<bool> cancelled,
      Value<DateTime?> newDate,
      Value<int?> newStartMinute,
      Value<int?> newEndMinute,
      Value<String?> newLocation,
      Value<String?> newTitle,
      Value<DateTime> createdAt,
    });
typedef $$OccurrenceOverridesTableUpdateCompanionBuilder =
    OccurrenceOverridesCompanion Function({
      Value<int> id,
      Value<int> ruleId,
      Value<DateTime> originalDate,
      Value<bool> cancelled,
      Value<DateTime?> newDate,
      Value<int?> newStartMinute,
      Value<int?> newEndMinute,
      Value<String?> newLocation,
      Value<String?> newTitle,
      Value<DateTime> createdAt,
    });

final class $$OccurrenceOverridesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $OccurrenceOverridesTable,
          OccurrenceOverride
        > {
  $$OccurrenceOverridesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CourseRulesTable _ruleIdTable(_$AppDatabase db) => db.courseRules
      .createAlias('occurrence_overrides__rule_id__course_rules__id');

  $$CourseRulesTableProcessedTableManager get ruleId {
    final $_column = $_itemColumn<int>('rule_id')!;

    final manager = $$CourseRulesTableTableManager(
      $_db,
      $_db.courseRules,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ruleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OccurrenceOverridesTableFilterComposer
    extends Composer<_$AppDatabase, $OccurrenceOverridesTable> {
  $$OccurrenceOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get originalDate => $composableBuilder(
    column: $table.originalDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get cancelled => $composableBuilder(
    column: $table.cancelled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get newDate => $composableBuilder(
    column: $table.newDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get newStartMinute => $composableBuilder(
    column: $table.newStartMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get newEndMinute => $composableBuilder(
    column: $table.newEndMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get newLocation => $composableBuilder(
    column: $table.newLocation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get newTitle => $composableBuilder(
    column: $table.newTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CourseRulesTableFilterComposer get ruleId {
    final $$CourseRulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ruleId,
      referencedTable: $db.courseRules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRulesTableFilterComposer(
            $db: $db,
            $table: $db.courseRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OccurrenceOverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $OccurrenceOverridesTable> {
  $$OccurrenceOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get originalDate => $composableBuilder(
    column: $table.originalDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get cancelled => $composableBuilder(
    column: $table.cancelled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get newDate => $composableBuilder(
    column: $table.newDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get newStartMinute => $composableBuilder(
    column: $table.newStartMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get newEndMinute => $composableBuilder(
    column: $table.newEndMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get newLocation => $composableBuilder(
    column: $table.newLocation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get newTitle => $composableBuilder(
    column: $table.newTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CourseRulesTableOrderingComposer get ruleId {
    final $$CourseRulesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ruleId,
      referencedTable: $db.courseRules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRulesTableOrderingComposer(
            $db: $db,
            $table: $db.courseRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OccurrenceOverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OccurrenceOverridesTable> {
  $$OccurrenceOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get originalDate => $composableBuilder(
    column: $table.originalDate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get cancelled =>
      $composableBuilder(column: $table.cancelled, builder: (column) => column);

  GeneratedColumn<DateTime> get newDate =>
      $composableBuilder(column: $table.newDate, builder: (column) => column);

  GeneratedColumn<int> get newStartMinute => $composableBuilder(
    column: $table.newStartMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get newEndMinute => $composableBuilder(
    column: $table.newEndMinute,
    builder: (column) => column,
  );

  GeneratedColumn<String> get newLocation => $composableBuilder(
    column: $table.newLocation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get newTitle =>
      $composableBuilder(column: $table.newTitle, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CourseRulesTableAnnotationComposer get ruleId {
    final $$CourseRulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ruleId,
      referencedTable: $db.courseRules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRulesTableAnnotationComposer(
            $db: $db,
            $table: $db.courseRules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OccurrenceOverridesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OccurrenceOverridesTable,
          OccurrenceOverride,
          $$OccurrenceOverridesTableFilterComposer,
          $$OccurrenceOverridesTableOrderingComposer,
          $$OccurrenceOverridesTableAnnotationComposer,
          $$OccurrenceOverridesTableCreateCompanionBuilder,
          $$OccurrenceOverridesTableUpdateCompanionBuilder,
          (OccurrenceOverride, $$OccurrenceOverridesTableReferences),
          OccurrenceOverride,
          PrefetchHooks Function({bool ruleId})
        > {
  $$OccurrenceOverridesTableTableManager(
    _$AppDatabase db,
    $OccurrenceOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OccurrenceOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OccurrenceOverridesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OccurrenceOverridesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> ruleId = const Value.absent(),
                Value<DateTime> originalDate = const Value.absent(),
                Value<bool> cancelled = const Value.absent(),
                Value<DateTime?> newDate = const Value.absent(),
                Value<int?> newStartMinute = const Value.absent(),
                Value<int?> newEndMinute = const Value.absent(),
                Value<String?> newLocation = const Value.absent(),
                Value<String?> newTitle = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => OccurrenceOverridesCompanion(
                id: id,
                ruleId: ruleId,
                originalDate: originalDate,
                cancelled: cancelled,
                newDate: newDate,
                newStartMinute: newStartMinute,
                newEndMinute: newEndMinute,
                newLocation: newLocation,
                newTitle: newTitle,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int ruleId,
                required DateTime originalDate,
                Value<bool> cancelled = const Value.absent(),
                Value<DateTime?> newDate = const Value.absent(),
                Value<int?> newStartMinute = const Value.absent(),
                Value<int?> newEndMinute = const Value.absent(),
                Value<String?> newLocation = const Value.absent(),
                Value<String?> newTitle = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => OccurrenceOverridesCompanion.insert(
                id: id,
                ruleId: ruleId,
                originalDate: originalDate,
                cancelled: cancelled,
                newDate: newDate,
                newStartMinute: newStartMinute,
                newEndMinute: newEndMinute,
                newLocation: newLocation,
                newTitle: newTitle,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OccurrenceOverridesTable, OccurrenceOverride>(
                    table,
                  ),
                  $$OccurrenceOverridesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ruleId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (ruleId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.ruleId,
                        referencedTable: $$OccurrenceOverridesTableReferences
                            ._ruleIdTable(db),
                        referencedColumn: $$OccurrenceOverridesTableReferences
                            ._ruleIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OccurrenceOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OccurrenceOverridesTable,
      OccurrenceOverride,
      $$OccurrenceOverridesTableFilterComposer,
      $$OccurrenceOverridesTableOrderingComposer,
      $$OccurrenceOverridesTableAnnotationComposer,
      $$OccurrenceOverridesTableCreateCompanionBuilder,
      $$OccurrenceOverridesTableUpdateCompanionBuilder,
      (OccurrenceOverride, $$OccurrenceOverridesTableReferences),
      OccurrenceOverride,
      PrefetchHooks Function({bool ruleId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CalendarSetsTableTableManager get calendarSets =>
      $$CalendarSetsTableTableManager(_db, _db.calendarSets);
  $$CourseRulesTableTableManager get courseRules =>
      $$CourseRulesTableTableManager(_db, _db.courseRules);
  $$OneOffEventsTableTableManager get oneOffEvents =>
      $$OneOffEventsTableTableManager(_db, _db.oneOffEvents);
  $$OccurrenceOverridesTableTableManager get occurrenceOverrides =>
      $$OccurrenceOverridesTableTableManager(_db, _db.occurrenceOverrides);
}
