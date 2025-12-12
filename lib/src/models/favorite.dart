class Favorite {
  /// 收藏记录自增 ID，用于分页
  int? id;

  /// 创建时间
  DateTime? createdAt;

  /// 业务侧的原始 itemId（这里是消息 seq）
  int? itemId;

  /// 业务类型，例如 "message"
  String? itemType;

  /// 原始数据（DataMessage 的 map）
  Map<String, dynamic>? data;

  /// 收藏附件持久化链接列表
  List<String>? attachments;

  Favorite({
    this.id,
    this.createdAt,
    this.itemId,
    this.itemType,
    this.data,
    this.attachments,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (id != null) {
      map['id'] = id;
    }
    if (createdAt != null) {
      map['create_at'] = createdAt!.toIso8601String();
    }
    if (itemId != null) {
      map['itemId'] = itemId;
    }
    if (itemType != null) {
      map['itemType'] = itemType;
    }
    if (data != null) {
      map['data'] = data;
    }
    if (attachments != null && attachments!.isNotEmpty) {
      map['attachments'] = attachments;
    }
    return map;
  }

  static Favorite fromMap(Map<String, dynamic> map) {
    return Favorite(
      id: map['id'],
      createdAt: map['create_at'] != null
          ? DateTime.tryParse(map['create_at'])
          : null,
      itemId: map['itemId'],
      itemType: map['itemType'],
      data: (map['data'] as Map?)?.cast<String, dynamic>(),
      attachments: (map['attachments'] as List?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }
}

