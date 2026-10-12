/// 界面语言。
///
/// 抽成常量而不是直接写进 `MaterialApp`，是为了让测试能拿**同一份**配置去起一个
/// 真的对话框。只断言「常量里有 'zh'」是废测试（自己写的自己看），而
/// 「弹出来的确实是中文」能挡住真正会犯的错 —— 漏掉某个 delegate、语言码写错
/// （`zh` 与 `zh_Hans` 不是一回事）、或者忘了把常量接到 `MaterialApp` 上。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 只声明中文，**不跟随系统语言**。
///
/// App 里所有文案都是写死的中文。跟随系统的话，英文系统上会变成「自己的中文 +
/// Material 弹窗的英文」混排 —— 而 Material 的弹窗恰恰是最常撞见的那几个
/// （选时间、选日期）。宁可中文界面在英文系统上也全中文，也不要半中半英。
///
/// 声明成单一语言后，`MaterialApp` 没有再指定 `locale` 的必要：直接没有别的可选。
const List<Locale> kSupportedLocales = <Locale>[Locale('zh')];

/// Material / Cupertino / Widgets 三家的本地化代理，缺一不可。
///
/// 少任何一家的后果都不是报错，而是那一类控件**悄悄退回英文**：
/// 少了 Widgets 的，`showDatePicker` 里的星期缩写会变英文。
const List<LocalizationsDelegate<dynamic>> kLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
