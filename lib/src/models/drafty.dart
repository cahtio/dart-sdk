import 'package:json_annotation/json_annotation.dart';

part 'drafty.g.dart';

/// 错误类型定义
sealed class DraftyError implements Exception {
  final String message;

  const DraftyError(this.message);
}

class IllegalArgumentError extends DraftyError {
  const IllegalArgumentError(super.message);
}

class InvalidIndexError extends DraftyError {
  const InvalidIndexError(super.message);
}

/// 格式化器接口（将Drafty节点转换为字符串表示）
abstract class DraftyFormatter<T> {
  T apply({
    String? type,
    Map<String, JsonValue>? data,
    int? key,
    required List<T> content,
    List<String>? stack,
  });

  T wrapText(String content);
}

/// 转换器接口（转换Span树节点）
abstract class DraftyTransformer {
  DraftySpan? transform(DraftySpan node);
}

/// 样式或实体引用
@JsonSerializable()
class Style {
  final int at;
  final int len;
  final String? tp;
  final int? key;

  Style({required this.at, required this.len, this.tp, this.key});

  /// 基础 inline 样式初始化
  factory Style.inline({String? tp, int at = 0, int len = 0}) {
    return Style(at: at, len: len, tp: tp, key: null);
  }

  /// 实体引用初始化
  factory Style.entity({int at = 0, int len = 0, int? key}) {
    return Style(at: at, len: len, tp: null, key: key);
  }

  factory Style.fromJson(Map<String, dynamic> json) => _$StyleFromJson(json);

  Map<String, dynamic> toJson() => _$StyleToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Style &&
          runtimeType == other.runtimeType &&
          at == other.at &&
          len == other.len &&
          tp == other.tp &&
          key == other.key;

  @override
  int get hashCode => at.hashCode ^ len.hashCode ^ tp.hashCode ^ key.hashCode;

  @override
  String toString() => 'Style(tp: $tp, at: $at, len: $len, key: $key)';
}

/// 实体（带附加数据的样式）
@JsonSerializable()
class Entity {
  final String? tp;
  final dynamic data;

  static const List<String> kLightData = [
    'mime',
    'name',
    'width',
    'height',
    'size',
  ];

  Entity({this.tp, this.data});

  factory Entity.fromJson(Map<String, dynamic> json) => _$EntityFromJson(json);

  Map<String, dynamic> toJson() => _$EntityToJson(this);

  /// 创建轻量副本（仅保留关键数据）
  Entity copyLight() {
    Map<String, dynamic>? lightData;
    if (data != null && data!.isNotEmpty) {
      lightData = {};
      for (final key in kLightData) {
        if (data!.containsKey(key)) {
          lightData[key] = data![key]!;
        }
      }
      if (lightData.isEmpty) lightData = null;
    }
    return Entity(tp: tp, data: lightData);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Entity &&
          runtimeType == other.runtimeType &&
          tp == other.tp &&
          _dataEquals(data, other.data);

  bool _dataEquals(Map<String, JsonValue>? a, Map<String, JsonValue>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => tp.hashCode ^ data.hashCode;

  @override
  String toString() => 'Entity(tp: $tp, data: $data)';
}

/// 带格式的文本及附件处理类
@JsonSerializable(anyMap: true)
class Drafty {
  static const String kMimeType = 'text/x-drafty';
  static const String kJSONMimeType = 'application/json+drafty';
  static const String kJSONMimeTypeLegacy = 'application/json';

  static const int kMaxFormElements = 8;
  static const int kMaxPreviewDataSize = 64;
  static const int kMaxPreviewAttachments = 3;

  static const List<String> kVoidStyles = ['BR', 'EX', 'HD'];
  static const List<String> kKnownDataFields = [
    'act',
    'duration',
    'height',
    'incoming',
    'mime',
    'name',
    'premime',
    'preview',
    'preref',
    'ref',
    'size',
    'state',
    'title',
    'url',
    'val',
    'vc',
    'width',
  ];

  /// 内联样式正则（对应Swift的kInlineStyles）
  static final Map<String, RegExp> kInlineStyles = {
    'ST': RegExp(r'(?<=^|[\W_])\*([^*]+[^\s*])\*(?=$|[\W_])'), // 粗体 *text*
    'EM': RegExp(r'(?<=^|\W)_([^_]+[^\s_])_(?=$|\W)'), // 斜体 _text_
    'DL': RegExp(r'(?<=^|[\W_])~([^~]+[^\s~])~(?=$|[\W_])'), // 删除线 ~text~
    'CO': RegExp(r'(?<=^|\W)`([^`]+)`(?=$|\W)'), // 代码 `text`
  };

  final String txt;
  final List<Style>? fmt;
  final List<Entity>? ent;

  bool get hasRefEntity =>
      ent?.any((e) => e.data?.containsKey('ref') ?? false) ?? false;

  int get length => txt.length;

  Drafty({this.txt = '', this.fmt, this.ent});

  /// 从纯文本初始化
  factory Drafty.plainText(String text) => Drafty(txt: text);

  /// 从带格式的内容解析初始化
  factory Drafty.fromContent(String content) {
    final parsed = _parse(content);
    return Drafty(txt: parsed.txt, fmt: parsed.fmt, ent: parsed.ent);
  }

  factory Drafty.fromJson(Map<String, dynamic> json) {
    return _$DraftyFromJson(json);
  }

  Map<String, dynamic> toJson() => _$DraftyToJson(this);

  /// 检查是否为纯文本（无格式和实体）
  bool get isPlain =>
      fmt == null || fmt!.isEmpty && ent == null || ent!.isEmpty;

  /// 获取实体引用
  List<String>? get entReferences {
    final refs = <String>[];
    if (ent == null) return null;
    for (final e in ent!) {
      if (e.data?.containsKey('ref') ?? false) {
        final ref = e.data!['ref'] as String?;
        if (ref != null) refs.add(ref.toString());
      }
      if (e.data?.containsKey('preref') ?? false) {
        final preref = e.data!['preref'] as String?;
        if (preref != null) refs.add(preref.toString());
      }
    }
    return refs.isEmpty ? null : refs;
  }

  /// 根据样式获取对应的实体
  Entity? entityFor(Style style) {
    final index = style.key ?? 0;
    if (ent == null || index < 0 || index >= ent!.length) return null;
    return ent![index];
  }

  // 以下为核心功能实现（解析、插入媒体、格式化等）
  // 完整实现需包含：_parse、insertImage、attachFile、quote等方法
  // 此处省略部分重复逻辑，保持核心结构

  /// 转换为Markdown
  String toMarkdown({bool plainLinks = false}) {
    final tree = _toSpanTree();
    final formatter = _MarkdownFormatter(plainLinks: plainLinks);
    return _treeBottomUp(tree, formatter) ?? '';
  }

  /// 内部方法：构建Span树
  DraftySpan? _toSpanTree() {
    // 实现逻辑与Swift的toTree类似
    // 处理样式和实体，构建嵌套的Span结构
    return DraftySpan(text: txt); // 简化示例
  }

  /// 内部方法：解析文本为Drafty结构
  static Drafty _parse(String content) {
    // 实现逻辑与Swift的parse类似
    // 处理换行、正则匹配样式和实体
    return Drafty.plainText(content); // 简化示例
  }

  /// 内部方法：遍历Span树并格式化
  static T? _treeBottomUp<T>(
    DraftySpan? src,
    DraftyFormatter<T> formatter, {
    List<String>? stack,
  }) {
    if (src == null) return null;
    var currentStack = List<String>.from(stack ?? []);
    if (!src.isUnstyled) {
      currentStack.add(src.type!);
    }

    final content = <T>[];
    if (src.children != null) {
      for (final child in src.children!) {
        final childResult = _treeBottomUp(
          child,
          formatter,
          stack: currentStack,
        );
        if (childResult != null) content.add(childResult);
      }
    } else if (src.text != null) {
      content.add(formatter.wrapText(src.text!));
    }

    return formatter.apply(
      type: src.type,
      data: src.data,
      key: src.key,
      content: content,
      stack: stack,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Drafty &&
          runtimeType == other.runtimeType &&
          txt == other.txt &&
          _fmtEquals(fmt, other.fmt) &&
          _entEquals(ent, other.ent);

  bool _fmtEquals(List<Style>? a, List<Style>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _entEquals(List<Entity>? a, List<Entity>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => txt.hashCode ^ fmt.hashCode ^ ent.hashCode;

  @override
  String toString() => 'Drafty(txt: "$txt", fmt: $fmt, ent: $ent)';
}

/// Markdown格式化器（实现DraftyFormatter）
class _MarkdownFormatter implements DraftyFormatter<String> {
  final bool plainLinks;

  _MarkdownFormatter({required this.plainLinks});

  @override
  String apply({
    String? type,
    Map<String, JsonValue>? data,
    int? key,
    required List<String> content,
    List<String>? stack,
  }) {
    final res = content.join();
    if (type == null) return res;

    switch (type) {
      case 'BR':
        return '\n';
      case 'HT':
        return '#$res';
      case 'MN':
        return '@$res';
      case 'ST':
        return '*$res*';
      case 'EM':
        return '_${res}_';
      case 'DL':
        return '~$res~';
      case 'CO':
        return '`$res`';
      case 'LN':
        if (!plainLinks) {
          final url = (data?['url'] as String?) ?? 'nil';
          return '[$res]($url)';
        }
        return res;
      default:
        return res;
    }
  }

  @override
  String wrapText(String content) => content;
}

/// 用于构建格式化树的节点
class DraftySpan {
  DraftySpan? parent;
  int start;
  int end;
  int key;
  String? text;
  String? type;
  Map<String, JsonValue>? data;
  List<DraftySpan>? children;
  bool attachment;

  DraftySpan({
    this.parent,
    this.start = 0,
    this.end = 0,
    this.key = 0,
    this.text,
    this.type,
    this.data,
    this.children,
    this.attachment = false,
  });

  /// 从文本创建
  factory DraftySpan.text(String text) => DraftySpan(text: text);

  /// 从样式创建
  factory DraftySpan.style(String? type, int start, int end) =>
      DraftySpan(type: type, start: start, end: end);

  /// 从实体引用创建
  factory DraftySpan.entity(int start, int end, int index) =>
      DraftySpan(start: start, end: end, key: index);

  /// 添加子节点
  DraftySpan append(DraftySpan child) {
    children ??= [];
    child.parent = this;
    children!.add(child);
    return this;
  }

  /// 检查是否为无样式节点
  bool get isUnstyled => type == null || type!.isEmpty;

  /// 检查是否为_void样式
  bool get isVoid => Drafty.kVoidStyles.contains(type ?? '');
}

/// 解析过程中的块级结构
class Block {
  String txt;
  List<Style>? fmt;

  Block(this.txt);

  void addStyle(Style s) {
    fmt ??= [];
    fmt!.add(s);
  }
}
