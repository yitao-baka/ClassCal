/// 测试用的临时目录 —— 建了就负责删，而且**删不掉不算失败**。
///
/// 不是测试文件（不以 `_test.dart` 结尾），所以测试跑手不会去跑它。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 建一个临时目录，并登记「跑完删掉」。
///
/// **删除刻意吞掉失败**，理由是一条具体的 Windows 行为：设置文件是
/// 「先写 `.tmp` 再改名」写出来的（`SettingsStore.save`），改名之后的一小段时间里
/// 杀软 / 索引器还捏着那个句柄，`deleteSync` 会被 errno 32
/// （「另一个程序正在使用此文件，进程无法访问。」）挡下来。
///
/// 实测：完整跑一次 `flutter test`，这条大约每三次红两次，而且**落在哪个测试上
/// 是随机的** —— 报的错跟被测代码毫无关系，只是那一个刚好收了尾。单跑那一个
/// 文件却是全绿的，于是它看起来像「偶发」而不像「有 bug」，就一直挂着没人管。
///
/// 删不掉的是系统临时目录里的一个文件夹，重试两次还不行就没有再做点什么的理由；
/// 但**绝不能让它把测试判红** —— 一次偶发的红色会训练人开始忽略红色，
/// 而那比留下一个空文件夹贵得多。
Directory tempDirForTest(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  // 登记在**这里**、而不是各测试文件自己的收尾块里，还顺带解决了一个顺序问题：
  // `addTearDown` 是后进先出，所以这个删除会排在后面登记的收尾动作（拆容器、
  // 关库）之后 —— 正是「先收干净，再删目录」该有的顺序，不必每处再手写一遍。
  addTearDown(() => _deleteQuietly(dir));
  return dir;
}

void _deleteQuietly(Directory dir, [int attempt = 0]) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // 第一次失败先歇一下再试：句柄通常几毫秒就松了。
    if (attempt >= 2) return;
    sleep(const Duration(milliseconds: 50));
    _deleteQuietly(dir, attempt + 1);
  }
}
