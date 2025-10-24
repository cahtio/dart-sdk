class DelRange {
  int? low; // 下限，包含
  int? hi; // 上限，包含
  bool? all;  // 是否删除所有消息

  DelRange({
    this.low,
    this.hi,
    this.all,
  });
  /// 从消息中创建删除范围
  static DelRange fromMessage(Map<String, dynamic> msg) {
    return DelRange(
      low: msg['low'],
      hi: msg['hi'],
      all: msg['all'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'low': low,
      'hi': hi,
      'all': all
    };
  }
}
