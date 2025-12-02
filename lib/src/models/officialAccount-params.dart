import 'package:tinode/src/models/topic-description.dart';

/// 官方账号创建参数类
class OfficialAccountParams {
  
  /// 设置参数
  final OfficialAccountSetParams? setParams;
  
  /// 获取参数
  final OfficialAccountGetParams? getParams;

  OfficialAccountParams({
    this.setParams,
    this.getParams,
  });

  /// 转换为Map格式
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
        if (setParams != null) map['set'] = setParams!.toMap();
    if (getParams != null) map['get'] = getParams!.toMap();
    
    return map;
  }
}

/// 官方账号设置参数
class OfficialAccountSetParams {
  /// 主题描述信息
  final TopicDescription? desc;
  
  /// 标签列表
  final List<String>? tags;

  OfficialAccountSetParams({
    this.desc,
    this.tags,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    
    if (desc != null) {
      final descMap = <String, dynamic>{};
      if (desc!.public != null) descMap['public'] = desc!.public;
      if (desc!.private != null) descMap['private'] = desc!.private;
      if (desc!.apply != null) descMap['apply'] = desc!.apply;
      map['desc'] = descMap;
    }
    
    if (tags != null) map['tags'] = tags;
    
    return map;
  }
}

/// 官方账号获取参数
class OfficialAccountGetParams {
  /// 数据查询参数
  final OfficialAccountDataParams? data;
  
  /// 查询内容标识
  final String? what;

  OfficialAccountGetParams({
    this.data,
    this.what,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    
    if (data != null) map['data'] = data!.toMap();
    if (what != null) map['what'] = what;
    
    return map;
  }
}

/// 官方账号数据查询参数
class OfficialAccountDataParams {
  /// 限制数量
  final int? limit;

  OfficialAccountDataParams({
    this.limit,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    
    if (limit != null) map['limit'] = limit;
    
    return map;
  }
}