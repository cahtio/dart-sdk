import 'package:tinode/src/models/topic-description.dart';
import 'package:tinode/src/models/topic-subscription.dart';
import 'package:tinode/src/models/credential.dart';
import 'package:tinode/src/models/favorite.dart';

class SetParams {
  TopicDescription? desc;
  TopicSubscription? sub;
  List<String>? tags;
  Credential? cred;
  List<String>? attachments;
  Favorite? favorite;

  SetParams({
    this.desc,
    this.sub,
    this.tags,
    this.cred,
    this.attachments,
    this.favorite,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (desc != null) {
      final descMap = <String, dynamic>{};
      if (desc!.private != null) {
        descMap['private'] = desc!.private;
      }
      if (desc!.public != null) {
        descMap['public'] = desc!.public;
      }
      map['desc'] = descMap;
    }
    if (favorite != null) {
      map['favorite'] = favorite!.toMap();
    }
    return map;
  }
}
