/// 界面语言的回归测试。
///
/// 起因是一个真机上撞见的问题：`showTimePicker` 弹出的是英文的
/// "Select time / Cancel / OK"，而周围全是中文。原因是 `MaterialApp` 没有声明
/// `localizationsDelegates`/`supportedLocales` —— 这两行少了的后果**不是报错**，
/// 是 Material 自带的控件按设备语言渲染，而设备上是英文。
///
/// 所以这里**真的把一个对话框弹出来**再断言它的字。只断言常量里含 'zh' 是废测试：
/// 常量是自己写的，改坏了接线（`MaterialApp` 上没接）它也照样绿。
library;

import 'dart:io';

import 'package:classcal/app/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 起一个最小 App，用的就是产品代码里的那份语言配置。
///
/// 刻意不整个起 `ClassCalApp`：那要拖上数据库、设置存储、提醒同步一整条链，
/// 而这里要验的只是**语言配置**这一件事。用 [kLocalizationsDelegates] /
/// [kSupportedLocales] 而不是自己另写一份，是为了让这个测试盯的是产品配置。
Future<void> _pumpLocalized(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: kLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('选时间弹窗是中文的', (tester) async {
    await _pumpLocalized(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showTimePicker(
            context: context,
            initialTime: const TimeOfDay(hour: 14, minute: 30),
          ),
          child: const Text('打开'),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing, reason: '这正是真机上看到的英文');
    expect(find.text('OK'), findsNothing);
  });

  testWidgets('选日期弹窗也是中文的', (tester) async {
    await _pumpLocalized(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDatePicker(
            context: context,
            initialDate: DateTime(2026, 10, 10),
            firstDate: DateTime(2026),
            lastDate: DateTime(2027),
          ),
          child: const Text('打开'),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
  });

  testWidgets('三家的 delegate 一个都不能少', (tester) async {
    // 少任意一家的后果都不是报错，而是那一类控件悄悄退回英文，
    // 所以这里逐个点名要它们在场。
    expect(
      kLocalizationsDelegates,
      containsAll(<LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ]),
    );
  });

  group('接线', () {
    // 上面那几条验的是「配置本身对不对」。但当初的 bug 不是配置写错了 ——
    // `MaterialApp` 上**压根没写这两行**。而配置对了、没接上去，上面几条测试
    // 照样全绿。所以这里回到源头看一眼：那两行还在不在。
    //
    // 直接读源码来断言是不得已 —— 起真正的 `ClassCalApp` 要拖上数据库、设置
    // 存储、提醒同步一整条链，为了验两个参数不值当。同样的手法在
    // `wallpaper_test.dart` 里也用了（那边核的是 Kotlin 侧的键名）。
    test('main.dart 里 MaterialApp 确实接了语言配置', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains('localizationsDelegates: kLocalizationsDelegates'),
        reason: '少了这行，选时间弹窗会退回英文，而且不报任何错',
      );
      expect(
        source,
        contains('supportedLocales: kSupportedLocales'),
        reason: '只给 delegate 不给 supportedLocales，语言仍然解析不到中文',
      );
    });
  });
}
