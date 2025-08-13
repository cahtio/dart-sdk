// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credential.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Credential _$CredentialFromJson(Map<String, dynamic> json) => Credential(
  meth: json['meth'] as String?,
  val: json['val'] as String?,
  resp: json['resp'] as String?,
  params: json['params'] as Map<String, dynamic>?,
  done: json['done'] as bool?,
);

Map<String, dynamic> _$CredentialToJson(Credential instance) =>
    <String, dynamic>{
      'meth': instance.meth,
      'val': instance.val,
      'resp': instance.resp,
      'done': instance.done,
      'params': instance.params,
    };
