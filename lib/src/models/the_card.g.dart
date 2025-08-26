// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'the_card.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Photo _$PhotoFromJson(Map<String, dynamic> json) => Photo(
  type: json['type'] as String? ?? Photo.kDefaultType,
  data: _$JsonConverterFromJson<String, Uint8List>(
    json['data'],
    const Base64Converter().fromJson,
  ),
  ref: json['ref'] as String?,
  width: (json['width'] as num?)?.toInt(),
  height: (json['height'] as num?)?.toInt(),
);

Map<String, dynamic> _$PhotoToJson(Photo instance) => <String, dynamic>{
  'type': instance.type,
  'data': _$JsonConverterToJson<String, Uint8List>(
    instance.data,
    const Base64Converter().toJson,
  ),
  'ref': instance.ref,
  'width': instance.width,
  'height': instance.height,
};

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) => json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) => value == null ? null : toJson(value);

Organization _$OrganizationFromJson(Map<String, dynamic> json) =>
    Organization(fn: json['fn'] as String?, title: json['title'] as String?);

Map<String, dynamic> _$OrganizationToJson(Organization instance) =>
    <String, dynamic>{'fn': instance.fn, 'title': instance.title};

Contact _$ContactFromJson(Map<String, dynamic> json) =>
    Contact(type: json['type'] as String?, uri: json['uri'] as String?);

Map<String, dynamic> _$ContactToJson(Contact instance) => <String, dynamic>{
  'type': instance.type,
  'uri': instance.uri,
};

Name _$NameFromJson(Map<String, dynamic> json) => Name(
  surname: json['surname'] as String?,
  given: json['given'] as String?,
  additional: json['additional'] as String?,
  prefix: json['prefix'] as String?,
  suffix: json['suffix'] as String?,
);

Map<String, dynamic> _$NameToJson(Name instance) => <String, dynamic>{
  'surname': instance.surname,
  'given': instance.given,
  'additional': instance.additional,
  'prefix': instance.prefix,
  'suffix': instance.suffix,
};

Birthday _$BirthdayFromJson(Map<String, dynamic> json) => Birthday(
  y: (json['y'] as num?)?.toInt(),
  m: (json['m'] as num?)?.toInt(),
  d: (json['d'] as num?)?.toInt(),
);

Map<String, dynamic> _$BirthdayToJson(Birthday instance) => <String, dynamic>{
  'y': instance.y,
  'm': instance.m,
  'd': instance.d,
};

TheCard _$TheCardFromJson(Map<String, dynamic> json) => TheCard(
  fn: json['fn'] as String?,
  n: json['n'] == null
      ? null
      : Name.fromJson(json['n'] as Map<String, dynamic>),
  org: json['org'] == null
      ? null
      : Organization.fromJson(json['org'] as Map<String, dynamic>),
  tel: (json['tel'] as List<dynamic>?)
      ?.map((e) => Contact.fromJson(e as Map<String, dynamic>))
      .toList(),
  email: (json['email'] as List<dynamic>?)
      ?.map((e) => Contact.fromJson(e as Map<String, dynamic>))
      .toList(),
  impp: (json['impp'] as List<dynamic>?)
      ?.map((e) => Contact.fromJson(e as Map<String, dynamic>))
      .toList(),
  photo: json['photo'] == null
      ? null
      : Photo.fromJson(json['photo'] as Map<String, dynamic>),
  bday: json['bday'] == null
      ? null
      : Birthday.fromJson(json['bday'] as Map<String, dynamic>),
  note: json['note'] as String?,
);

Map<String, dynamic> _$TheCardToJson(TheCard instance) => <String, dynamic>{
  'fn': instance.fn,
  'n': instance.n,
  'org': instance.org,
  'tel': instance.tel,
  'email': instance.email,
  'impp': instance.impp,
  'photo': instance.photo,
  'bday': instance.bday,
  'note': instance.note,
};
