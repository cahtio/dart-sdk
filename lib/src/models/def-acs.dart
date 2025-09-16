import 'package:tinode/src/models/acs-helper.dart';

/// Topic's default access permissions
class DefAcs {
  /// Default access for authenticated users
  AcsHelper auth;

  /// Default access for anonymous users
  AcsHelper anon;

  DefAcs(this.auth, this.anon);

  DefAcs.fromString(String? auth, String? anon)
      : auth = AcsHelper.fromString(auth),
        anon = AcsHelper.fromString(anon);

  DefAcs.fromAcs(DefAcs acs)
      : auth = AcsHelper.fromHelper(acs.auth),
        anon = AcsHelper.fromHelper(acs.anon);

  static DefAcs fromMessage(Map<String, dynamic> msg) {
    return DefAcs(
        AcsHelper.fromString(msg['auth']), AcsHelper.fromString(msg['anon']));
  }

  bool update(String? auth, String? anon) {
    var changed = false;
    if (auth != null) {
      changed = this.auth.update(auth);
    }
    if (anon != null) {
      changed = changed || this.anon.update(anon);
    }
    return changed;
  }

  Map<String, dynamic> toJson() {
    return {'auth': auth.toString(), 'anon': anon.toString()};
  }
}
