import 'dart:convert';

import 'package:tinode/src/models/topic-subscription.dart';

class User {
  DateTime? updated;
  String? uid;
  dynamic pub;
  dynamic payload;

  User({this.uid, this.updated, this.pub});

  // 从 Description 构造
  // User.fromDesc({String? uid, required Description<P, dynamic> desc})
  //   : this(uid: uid, updated: desc.updated, pub: desc.pub);

  // 从 Subscription 构造
  User.fromSub(TopicSubscription sub) {
    if (sub.user == null || sub.user!.isEmpty) {
      throw InvalidUserException('Invalid subscription param: missing uid');
    }
    uid = sub.user;
    updated = sub.updated;
    pub = sub.public;
  }

  static User? createFromPublicData({
    String? uid,
    DateTime? updated,
    String? data,
  }) {
    if (data == null) return null;
    return User(uid: uid, updated: updated, pub: json.decode(data));
  }

  String? serializePub() {
    return pub != null ? json.decode(pub!) : null;
  }

  bool mergeFrom(User user) {
    var changed = false;
    if (user.updated != null &&
        (updated == null || updated!.isBefore(user.updated!))) {
      updated = user.updated;
      if (user.pub != null) pub = user.pub;
      changed = true;
    } else if (pub == null && user.pub != null) {
      pub = user.pub;
      changed = true;
    }
    return changed;
  }

  // bool mergeFromDesc<DR>(Description<P, DR> desc) {
  //   var changed = false;
  //   if (desc.updated != null &&
  //       (updated == null || updated!.isBefore(desc.updated!))) {
  //     updated = desc.updated;
  //     if (desc.pub != null) pub = desc.pub;
  //     changed = true;
  //   } else if (pub == null && desc.pub != null) {
  //     pub = desc.pub;
  //     changed = true;
  //   }
  //   return changed;
  // }

  bool mergeFromSub(TopicSubscription sub) {
    var changed = false;
    if (sub.updated != null &&
        (updated == null || updated!.isBefore(sub.updated!))) {
      updated = sub.updated;
      if (sub.public != null) pub = sub.public;
      changed = true;
    } else if (pub == null && sub.public != null) {
      pub = sub.public;
      changed = true;
    }
    return changed;
  } 
}

class InvalidUserException implements Exception {
  final String message;

  InvalidUserException(this.message);
}
