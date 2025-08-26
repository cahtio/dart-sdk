import 'package:tinode/tinode.dart';

abstract interface class Mergeable {
  bool merge(Mergeable another);
}

extension StringMergeable on String {
  bool merge(Mergeable another) {
    if (another is! String) return false;
    return true;
  }
}

typedef PrivateType = Map<String, dynamic>;

extension PrivateTypeMergeable on PrivateType {
  bool? getBoolValue(String name) {
    return this[name] as bool?;
  }

  String? getStringValue(String name) {
    return this[name] as String?;
  }

  String? get comment {
    return this['comment'] as String?;
  }

  set comment(String? newValue) {
    this['comment'] = newValue ?? Tinode.kNullValue;
  }

  bool? get archived {
    return this['arch'] as bool?;
  }

  set archived(bool? newValue) {
    this['arch'] = newValue;
  }

  bool merge(Mergeable another) {
    if (another is! PrivateType) return false;
    final anotherPT = another as PrivateType;
    for (var entry in anotherPT.entries) {
      this[entry.key] = entry.value;
    }
    return anotherPT.isNotEmpty;
  }
}
