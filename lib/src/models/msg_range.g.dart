// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'msg_range.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MsgRange _$MsgRangeFromJson(Map<String, dynamic> json) => MsgRange(
  low: (json['low'] as num?)?.toInt() ?? 0,
  hi: (json['hi'] as num?)?.toInt(),
);

Map<String, dynamic> _$MsgRangeToJson(MsgRange instance) => <String, dynamic>{
  'low': instance.low,
  'hi': instance.hi,
};
