// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drafty.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Style _$StyleFromJson(Map<String, dynamic> json) => Style(
  at: (json['at'] as num).toInt(),
  len: (json['len'] as num).toInt(),
  tp: json['tp'] as String?,
  key: (json['key'] as num?)?.toInt(),
);

Map<String, dynamic> _$StyleToJson(Style instance) => <String, dynamic>{
  'at': instance.at,
  'len': instance.len,
  'tp': instance.tp,
  'key': instance.key,
};

Entity _$EntityFromJson(Map<String, dynamic> json) =>
    Entity(tp: json['tp'] as String?, data: json['data']);

Map<String, dynamic> _$EntityToJson(Entity instance) => <String, dynamic>{
  'tp': instance.tp,
  'data': instance.data,
};

Drafty _$DraftyFromJson(Map json) => Drafty(
  txt: json['txt'] as String? ?? '',
  fmt: (json['fmt'] as List<dynamic>?)
      ?.map((e) => Style.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList(),
  ent: (json['ent'] as List<dynamic>?)
      ?.map((e) => Entity.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList(),
);

Map<String, dynamic> _$DraftyToJson(Drafty instance) => <String, dynamic>{
  'txt': instance.txt,
  'fmt': instance.fmt,
  'ent': instance.ent,
};
