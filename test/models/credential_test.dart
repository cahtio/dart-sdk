import 'dart:convert';


import 'package:test/test.dart';
import 'package:tinode/src/models/access-mode.dart';
import 'package:tinode/tinode.dart';

void main() {
  test('decode(null) returns null', () {
    var cred = Credential(
      meth: 'meth',
      val: 'val',
      resp: 'resp',
      params: {'one': 1},
      done: false,
    );
    var cred2 = Credential(
      meth: 'meth2',
      val: 'val2',
      resp: 'resp2',
      params: {'one': 2},
      done: false,
    );
    final list = [cred, cred2];
    // final jsonList = list.map((c) => c.toJson()).toList();
    final jsonString = '[]';
    print(jsonString);
    List<dynamic> newList = json.decode(jsonString);

    print(newList);
    final crdList = newList.map((json) => Credential.fromJson(json)).toList();
    print(crdList);


    // expect(AccessMode.decode(null), equals(null));
  });
}
