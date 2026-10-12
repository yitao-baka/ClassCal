/// 导出到文件。
///
/// 两种格式各司其职，UI 上都给，措辞也刻意区分开（见 `ics_export.dart` 的说明）：
///
/// * **ICS** —— 给别的日历软件用。导出的是解析完的最终时刻。
/// * **JSON** —— 给自己备份用。导出的是三层结构本身，连改期记录都在。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/exchange/classcal_json.dart';
import '../../data/exchange/ics_export.dart';

/// 把 [setId] 对应的一套课表导出成 ICS。
Future<void> exportIcsSet(
  BuildContext context,
  WidgetRef ref,
  int setId,
) async {
  final repo = ref.read(repositoryProvider);
  final set = await repo.loadSetData(setId);
  // 读库是异步的，读完之后这个页面可能已经被弹掉了
  if (set == null || !context.mounted) return;

  await _save(
    context,
    fileName: '${_safeName(set.name)}.ics',
    mimeType: 'text/calendar',
    text: exportIcs([set], calendarName: set.name),
    successLabel: '已导出 ICS',
  );
}

/// 把**全部**课表导出成一个 JSON 备份。
///
/// 备份是整个库一起备份的：「只备份其中一套」听起来合理，实际用起来
/// 是「恢复之后另一半不见了」的来源 —— 同一份文件里两套课表的 id 是
/// 互相引用的，拆开导出再合起来导入会撞 id。
Future<void> exportJsonBackup(BuildContext context, WidgetRef ref) async {
  final sets = await ref.read(repositoryProvider).loadAllSets();
  if (!context.mounted) return;
  if (sets.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('还没有日程可以备份')));
    return;
  }

  await _save(
    context,
    fileName: 'ClassCal备份_${_stamp(DateTime.now())}.json',
    mimeType: 'application/json',
    text: encodeSets(sets, exportedAt: DateTime.now()),
    successLabel: '已备份 ${sets.length} 个日程',
  );
}

/// 弹系统「保存到…」，把文本写成文件。
///
/// 返回是否真的保存了 —— 用户在选择器里按返回键取消是常事，
/// 那种情况下不该报「导出成功」，也不该报错。
Future<bool> _save(
  BuildContext context, {
  required String fileName,
  required String mimeType,
  required String text,
  required String successLabel,
}) async {
  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      // 用字节而不是字符串：saveFile 要的是 Uint8List，
      // 而中文文件名和内容都必须按 UTF-8 落盘。
      bytes: utf8.encode(text),
      mimeType: mimeType,
    );
    if (uri == null) return false; // 用户取消
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$successLabel：$fileName')),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    return false;
  }
}

/// 课表名要当文件名用，得先滤掉路径分隔符等非法字符。
String _safeName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'ClassCal' : cleaned;
}

String _stamp(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
