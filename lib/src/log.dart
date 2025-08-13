import 'package:flutter/foundation.dart';

enum LogType { debug, info, error, fault }

class Log {
  final String prefix;
  static final Log defaultLog = Log(subsystem: "default");

  Log({String subsystem = ""})
    : prefix = subsystem.isEmpty ? "[default] " : "[$subsystem] " {
    // 如果未提供子系统名称，尝试使用应用包名
    if (subsystem.isEmpty) {
      // 在Flutter中获取包名需要使用package_info_plus等插件
      // 这里保持默认值，实际使用时可根据需要修改
    }
  }

  void log(LogType type, String message, [List<dynamic> args = const []]) {
    // 在Dart中没有编译期的DEBUG宏定义，通常通过环境变量来区分
    if (kDebugMode && type == LogType.debug) {
      _printLog(type, message, args);
    }

    // 非调试模式下，除了debug类型都输出
    if (type != LogType.debug) {
      _printLog(type, message, args);
    }
  }

  void _printLog(LogType type, String message, List<dynamic> args) {
    String formattedMessage = prefix + message;

    // 处理格式化参数
    if (args.isNotEmpty) {
      formattedMessage = _formatMessage(formattedMessage, args);
    }

    // 添加日志类型前缀
    String typePrefix;
    switch (type) {
      case LogType.debug:
        typePrefix = "[DEBUG] ";
        break;
      case LogType.info:
        typePrefix = "[INFO] ";
        break;
      case LogType.error:
        typePrefix = "[ERROR] ";
        break;
      case LogType.fault:
        typePrefix = "[FAULT] ";
        break;
    }

    debugPrint("$typePrefix$formattedMessage");
  }

  String _formatMessage(String message, List<dynamic> args) {
    // 简单实现字符串格式化，类似printf
    var result = message;
    for (var arg in args) {
      result = result.replaceFirst(RegExp(r'%[a-zA-Z]'), arg.toString());
    }
    return result;
  }

  void debug(String message, [List<dynamic> args = const []]) {
    log(LogType.debug, message, args);
  }

  void info(String message, [List<dynamic> args = const []]) {
    log(LogType.info, message, args);
  }

  void error(String message, [List<dynamic> args = const []]) {
    log(LogType.error, message, args);
  }

  void fault(String message, [List<dynamic> args = const []]) {
    log(LogType.fault, message, args);
  }
}
