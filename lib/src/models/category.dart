
class Category {
  int? id;
  DateTime? createdAt;
  DateTime? updatedAt;
  String? name;
  int? parentId;
  int? level;
  int? sort;
  int? isShow;
  List<Category>? children;

  Category({
    this.id,
    this.createdAt,
    this.updatedAt,
    this.name,
    this.parentId,
    this.level,
    this.sort,
    this.isShow,
    this.children,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (id != null) {
      map['id'] = id;
    }
    if (createdAt != null) {
      map['createdAt'] = createdAt!.toIso8601String();
    }
    if (updatedAt != null) {
      map['updatedAt'] = updatedAt!.toIso8601String();
    }
    if (name != null) {
      map['name'] = name;
    }
    if (parentId != null) {
      map['parentId'] = parentId;
    }
    if (level != null) {
      map['level'] = level;
    }
    if (sort != null) {
      map['sort'] = sort;
    }
    if (isShow != null) {
      map['isShow'] = isShow;
    }
    if (children != null) {
      map['children'] = children!.map((child) => child.toMap()).toList();
    }
    return map;
  }

  static Category fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'])
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'])
          : null,
      name: map['name'],
      parentId: map['parentId'],
      level: map['level'],
      sort: map['sort'],
      isShow: map['isShow'],
      children: (map['children'] as List<dynamic>?)
          ?.map((child) => Category.fromMap(child))
          .toList(),
    );
  }
}