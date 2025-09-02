import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';
import 'package:tinode/src/converter/base64.dart';

import 'package:tinode/src/models/types.dart';
import 'package:tinode/tinode.dart';

part 'the_card.g.dart';

@JsonSerializable()
class Photo {
  static const kDefaultType = 'png';

  // The specific part of the image mime type, e.g. if mime type is "image/png", the type is "png".
  late final String? type;

  // Image bits.
  @Base64Converter()
  final Uint8List? data;

  // URL of the image for out-of-band avatars
  final String? ref;

  // Width and height of the image.
  final int? width;
  final int? height;

  Photo({
    String type = Photo.kDefaultType,
    this.data,
    this.ref,
    this.width,
    this.height,
  }) : type = _extractType(type);

  Photo.fromRef(String? ref, {String type = kDefaultType})
    : this(type: type, data: null, ref: ref, width: null, height: null);

  factory Photo.fromJson(Map<String, dynamic> json) => _$PhotoFromJson(json);

  static String _extractType(String tp) {
    // 从完整的mime类型中提取特定部分
    var parts = tp.split('/');

    if (parts.length > 1) {
      if (parts[0] == 'image') {
        // 去掉第一个组件"image/"，保留其余部分
        return parts.sublist(1).join('/');
      } else {
        // 无效的mime类型，使用默认值
        return kDefaultType;
      }
    } else {
      return tp;
    }
  }

  Map<String, dynamic> toJson() => _$PhotoToJson(this);

  Photo copy() => Photo(
    type: type ?? Photo.kDefaultType,
    data: data,
    ref: ref,
    width: width,
    height: height,
  );
}

@JsonSerializable()
class Organization {
  String? fn;
  String? title;

  Organization({this.fn, this.title});

  Organization copy() => Organization(fn: fn, title: title);

  factory Organization.fromJson(Map<String, dynamic> json) =>
      _$OrganizationFromJson(json);

  Map<String, dynamic> toJson() => _$OrganizationToJson(this);
}

@JsonSerializable()
class Contact {
  String? type;
  String? uri;

  Contact({this.type, this.uri});

  Contact copy() => Contact(type: type, uri: uri);

  factory Contact.fromJson(Map<String, dynamic> json) =>
      _$ContactFromJson(json);

  Map<String, dynamic> toJson() => _$ContactToJson(this);
}

@JsonSerializable()
class Name {
  String? surname;
  String? given;
  String? additional;
  String? prefix;
  String? suffix;

  Name({this.surname, this.given, this.additional, this.prefix, this.suffix});

  Name copy() => Name(
    surname: surname,
    given: given,
    additional: additional,
    prefix: prefix,
    suffix: suffix,
  );

  factory Name.fromJson(Map<String, dynamic> json) => _$NameFromJson(json);

  Map<String, dynamic> toJson() => _$NameToJson(this);
}

@JsonSerializable()
class Birthday {
  // Year like 1975
  int? y;

  // Month 1..12.
  int? m;

  // Day 1..31.
  int? d;

  Birthday({this.y, this.m, this.d});

  Birthday copy() => Birthday(y: y, m: m, d: d);

  factory Birthday.fromJson(Map<String, dynamic> json) =>
      _$BirthdayFromJson(json);

  Map<String, dynamic> toJson() => _$BirthdayToJson(this);
}

@JsonSerializable()
class TheCard implements Mergeable {
  String? fn;
  Name? n;
  Organization? org;

  // List of phone numbers associated with the contact.
  List<Contact>? tel;

  // List of contact's email addresses.
  List<Contact>? email;
  List<Contact>? impp;

  // Avatar photo.
  Photo? photo;
  Birthday? bday;

  // Free-form description.
  String? note;

  List<String>? get photoRefs {
    if (photo?.ref == null) return null;
    return [photo!.ref!];
  }

  Uint8List? get photoBits {
    return photo?.data;
  }

  String get photoMimeType => 'image/${photo?.type ?? Photo.kDefaultType}';

  TheCard({
    this.fn,
    this.n,
    this.org,
    this.tel,
    this.email,
    this.impp,
    this.photo,
    this.bday,
    this.note,
  });

  factory TheCard.fromJson(Map<String, dynamic> json) =>
      _$TheCardFromJson(json);

  Map<String, dynamic> toJson() => _$TheCardToJson(this);

  TheCard copy() => TheCard(
    fn: fn,
    n: n?.copy(),
    org: org?.copy(),
    tel: tel?.map((e) => e.copy()).toList(),
    email: email?.map((e) => e.copy()).toList(),
    impp: impp?.map((e) => e.copy()).toList(),
    photo: photo?.copy(),
    bday: bday?.copy(),
    note: note,
  );

  @override
  bool merge(Mergeable another) {
    if (another is! TheCard) return false;
    var changed = false;
    if (another.fn != null) {
      fn = !Tinode.isNull(another.fn) ? another.fn : null;
      changed = true;
    }
    if (another.org != null) {
      org = !Tinode.isNull(another.org) ? another.org : null;
      changed = true;
    }
    if (another.tel != null) {
      tel = !Tinode.isNull(another.tel) ? another.tel : null;
      changed = true;
    }
    if (another.email != null) {
      email = !Tinode.isNull(another.email) ? another.email : null;
      changed = true;
    }
    if (another.impp != null) {
      impp = !Tinode.isNull(another.impp) ? another.impp : null;
      changed = true;
    }
    if (another.photo != null) {
      photo = !Tinode.isNull(another.photo) ? another.photo!.copy() : null;
      changed = true;
    }
    if (another.bday != null) {
      bday = !Tinode.isNull(another.bday) ? another.bday!.copy() : null;
      changed = true;
    }
    if (another.note != null) {
      note = !Tinode.isNull(another.note) ? another.note : null;
      changed = true;
    }
    return changed;
  }
}
