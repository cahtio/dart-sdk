import 'package:json_annotation/json_annotation.dart';

part 'credential.g.dart';

/// A data structure representing a credential
@JsonSerializable()
class Credential {
  /// Validation method
  final String? meth;

  /// Validation value (e.g. email or phone number)
  final String? val;

  /// Validation response
  final String? resp;

  /// Check if validation done
  bool? done;

  /// Validation parameters
  final Map<String, dynamic>? params;

  // Create a new instance of Credential
  Credential({this.meth, this.val, this.resp, this.params, this.done});

  static Credential fromMessage(Map<String, dynamic> msg) {
    return Credential(meth: msg['meth'], val: msg['val'], done: msg['done']);
  }

  factory Credential.fromJson(Map<String, dynamic> json) =>
      _$CredentialFromJson(json);

  Map<String, dynamic> toJson() => _$CredentialToJson(this);

  @override
  String toString() {
    return 'Credential(${identityHashCode(this)}){meth: $meth, val: $val, resp: $resp, done: $done, params: $params}';
  }
}
