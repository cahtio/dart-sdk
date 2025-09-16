class AcsHelper {
  // J - join topic.
  static const kModeJoin = 0x01;
  // R - read broadcasts
  static const kModeRead = 0x02;
  // W - publish
  static const kModeWrite = 0x04;
  // P - receive presence notifications
  static const kModePres = 0x08;
  // A - approve requests
  static const kModeApprove = 0x10;
  // S - user can invite other people to join (S)
  static const kModeShare = 0x20;
  // D - user can hard-delete messages (D), only owner can completely delete
  static const kModeDelete = 0x40;
  // O - user is the owner (O) - full access
  static const kModeOwner = 0x80;
  // No access, requests to gain access are processed normally (N)
  static const kModeNone = 0;
  // Invalid mode to indicate an error
  static const kModeInvalid = 0x100000;

  static const _kModes = ['J', 'R', 'W', 'P', 'A', 'S', 'D', 'O'];

  int? _a;

  @override
  String toString() {
    if (_a == null) return '';
    return _encode(_a!);
  }

  /// The value is neither nil nor Invalid. None is considered to be defined.
  bool get isDefined => (_a ?? kModeInvalid) != kModeInvalid;

  bool get isOwner => ((_a ?? 0) & kModeOwner) != 0;

  bool get isAdmin => ((_a ?? 0) & kModeApprove) != 0;

  bool get isManager => isOwner || isAdmin;

  bool get isSharer => ((_a ?? 0) & kModeShare) != 0;

  bool get isMuted => ((_a ?? 0) & kModePres) == 0;

  bool get isInvalid => (_a ?? 0) == kModeInvalid;

  bool get isJoiner => ((_a ?? 0) & kModeJoin) != 0;

  bool get isReader => ((_a ?? 0) & kModeRead) != 0;

  bool get isWriter => ((_a ?? 0) & kModeWrite) != 0;

  bool get isDeleter => ((_a ?? 0) & kModeDelete) != 0;

  bool get isNone => (_a ?? -1) == kModeNone;

  AcsHelper.fromString(String? str) : _a = _decode(str);

  AcsHelper.fromHelper(AcsHelper? ah) : _a = ah?._a;

  AcsHelper(this._a);

  bool hasPermissions(int mode) {
    if (isInvalid) return false;
    return (_a! & mode) != 0;
  }

  static int _decode(String? modeStr) {
    if (modeStr == null || modeStr.isEmpty) return kModeInvalid;

    var m0 = kModeNone;
    final modeUpper = modeStr.toUpperCase();

    for (var c in modeUpper.runes) {
      final char = String.fromCharCode(c);
      final idx = _kModes.indexOf(char);

      if (idx != -1) {
        m0 |= 1 << idx;
      } else {
        return char == 'N' ? kModeNone : kModeInvalid;
      }
    }

    return m0;
  }

  static String _encode(int mode) {
    if (mode == kModeInvalid) return '';

    if (mode == kModeNone) return 'N';

    final result = <String>[];
    for (var i = 0; i < _kModes.length; i++) {
      if (((mode >> i) & 1) != 0) {
        result.add(_kModes[i]);
      }
    }
    return result.join();
  }

  // Same as split() but retains the separators ["+", "-"]: "+ABC-DEF" -> ["+ABC", "-DEF"]
  static List<String> _tokenizeCommand(String str) {
    final result = <String>[];
    var temp = '';

    for (final c in str.runes) {
      final char = String.fromCharCode(c);
      if (char == '+' || char == '-') {
        if (temp.isNotEmpty) {
          result.add(temp);
          temp = '';
        }
      }
      temp += char;
    }

    if (temp.isNotEmpty) {
      result.add(temp);
    }

    return result;
  }

  bool update(String umode) {
    final oldA = _a;
    _a = _update(_a, umode);
    return _a != oldA;
  }

  static int? _update(int? mode, String command) {
    if (command.isEmpty) {
      return mode;
    }

    final action = command.isNotEmpty ? command[0] : null;
    int result;

    if (action == '+' || action == '-') {
      result = mode ?? 0;
      final parts = _tokenizeCommand(command);

      for (var p in parts) {
        if (p.isEmpty) continue;

        // 解析命令部分
        final m0 = _decode(p.substring(1));
        if (m0 == kModeInvalid) {
          throw FormatException('invalid value');
        }
        if (m0 == kModeNone) {
          continue;
        }

        if (p[0] == '+') {
          result |= m0;
        } else {
          result &= ~m0;
        }
      }
    } else {
      result = _decode(command);
      if (result == kModeInvalid) {
        throw FormatException('invalid value');
      }
    }

    return result;
  }

  bool merge(AcsHelper? ah) {
    if (ah == null || _a == null || _a == kModeInvalid) return false;

    final aha = ah._a;
    if (aha != null && aha != _a) {
      _a = aha;
      return true;
    }
    return false;
  }

  // Bitwise & operator.
  static AcsHelper? and(AcsHelper? a1, AcsHelper? a2) {
    if (a1 == null || a2 == null || a1.isInvalid || a2.isInvalid) {
      return null;
    }
    return AcsHelper(a1._a! & a2._a!);
  }

  // Bits present in a1 but missing in a2.
  static AcsHelper? diff(AcsHelper? a1, AcsHelper? a2) {
    if (a1 == null || a2 == null || a1.isInvalid || a2.isInvalid) {
      return null;
    }
    return AcsHelper(a1._a! & ~a2._a!);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcsHelper && runtimeType == other.runtimeType && _a == other._a;

  @override
  int get hashCode => _a.hashCode;
}
