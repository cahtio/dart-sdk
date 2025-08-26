import 'dart:convert';
import 'dart:typed_data';

import 'package:json_annotation/json_annotation.dart';

class Base64Converter implements JsonConverter<Uint8List, String> {
  const Base64Converter();

  @override
  Uint8List fromJson(String json) => base64.decode(json);

  @override
  String toJson(Uint8List object) => base64.encode(object);
}
