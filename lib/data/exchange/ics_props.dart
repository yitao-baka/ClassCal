/// 我们在 ICS 里附加的机器可读属性名。
///
/// 为什么必须要有这一组：周次和节次在 RFC 5545 里**没有位置**。标准日历只有
/// 「一个事件从某时刻到某时刻」，而「这门课第 5-16 周、每周一第 1-2 节」是
/// 课表特有的概念。若不额外记录，导出再导入就会退化成一堆互不相干的独立事件，
/// 周次结构彻底丢失 —— 用户看到的是一次成功的导入和一张面目全非的课表。
///
/// 所以生成 ICS 时把结构化信息写进这些 `X-` 属性：别的日历软件按标准忽略它们
/// （不会显示成乱码），我们自己读回来则是无损的。读不到时再退化为按时间反推。
///
/// 命名为 `X-CLASSCAL-*`，`X-` 前缀是 RFC 5545 给私有扩展留的命名空间。
library;

/// 该门课的全部上课周次，逗号分隔，例如 `5,6,7,8,9,10`。
const String kXWeeks = 'X-CLASSCAL-WEEKS';

/// 节次区间，例如 `1-2`。
const String kXPeriods = 'X-CLASSCAL-PERIODS';

/// 第 1 周的周一，`yyyy-MM-dd` —— 全部周次换算的锚点。
const String kXWeek1Monday = 'X-CLASSCAL-WEEK1MONDAY';

/// 任课教师。
const String kXTeacher = 'X-CLASSCAL-TEACHER';

/// 该套课表的显示名。
const String kXSetName = 'X-CLASSCAL-SETNAME';

/// 课程颜色种子，`#RRGGBB`。
const String kXColor = 'X-CLASSCAL-COLOR';
