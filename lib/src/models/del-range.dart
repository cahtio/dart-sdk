class DelRange {
  int? low; // 下限，包含
  int? hi; // 上限，包含
  bool? all; // 是否删除所有消息

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

  // 1. 自定义 == 相等判断
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DelRange &&
          runtimeType == other.runtimeType &&
          low == other.low &&
          hi == other.hi &&
          all == other.all;

  @override
  int get hashCode => low.hashCode ^ hi.hashCode ^ all.hashCode;

  Map<String, dynamic> toJson() {
    return {'low': low, 'hi': hi, 'all': all};
  }

  bool isContain(int seq) {
    if (low == null) return false;
    if (low! > seq) return false;
    if (hi == null) {
      return low == seq;
    } else {
      return hi! > seq;
    }
  }
}
