import 'package:json_annotation/json_annotation.dart';

part 'def-acs.g.dart';

/// Topic's default access permissions
@JsonSerializable()
class DefAcs {
  /// Default access for authenticated users
  String auth;

  /// Default access for anonymous users
  String anon;

  DefAcs(this.auth, this.anon);

  static DefAcs fromMessage(Map<String, dynamic> msg) {
    return DefAcs(msg['auth'], msg['anon']);
  }

  factory DefAcs.fromJson(Map<String, dynamic> json) => _$DefAcsFromJson(json);

  Map<String, dynamic> toJson() => _$DefAcsToJson(this);

  // 序列化方法
  String serialize() {
    return [auth, anon].join(',');
  }

  // 反序列化静态方法
  static DefAcs? deserialize(String? data) {
    if (data == null) return null;

    final parts = data.split(',');
    if (parts.length != 2) return null;

    return DefAcs(parts[0], parts[1]);
  }
}
