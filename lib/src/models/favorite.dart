class Favorite {
  int? itemId;
  String? itemType;
  Map<String, dynamic>? data;

  Favorite({this.itemId, this.itemType, this.data});

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (itemId != null) {
      map['itemId'] = itemId;
    }
    if (itemType != null) {
      map['itemType'] = itemType;
    }
    if (data != null) {
      map['data'] = data;
    }
    return map;
  }
}

