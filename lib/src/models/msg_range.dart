import 'package:json_annotation/json_annotation.dart';

part 'msg_range.g.dart';

@JsonSerializable()
class MsgRange implements Comparable<MsgRange> {
  int low;
  int? hi;

  int get lower => low;

  int get upper => hi ?? lower + 1;

  // 默认构造函数
  MsgRange({this.low = 0, this.hi});

  // 用单个ID初始化（表示单个元素范围）
  MsgRange.id(int id) : low = id, hi = null;

  // 用low和hi初始化
  MsgRange.withBounds(this.low, this.hi);

  // 从另一个MsgRange复制
  MsgRange.from(MsgRange another) : low = another.low, hi = another.hi;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MsgRange &&
          runtimeType == other.runtimeType &&
          lower == other.lower &&
          upper == other.upper;

  @override
  int get hashCode => lower.hashCode ^ upper.hashCode;

  @override
  int compareTo(MsgRange other) {
    var diff = low - other.low;
    if (diff == 0) {
      diff = other.upper - upper;
    }
    return diff;
  }

  bool operator <(MsgRange other) => compareTo(other) < 0;

  // 尝试用ID扩展当前范围
  bool _extend(int id) {
    if (low == id) {
      return true;
    }
    if (hi != null) {
      if (hi == id) {
        hi = hi! + 1;
        return true;
      }
      return false;
    }
    // hi为null的情况
    if (id == low + 1) {
      hi = id + 1;
      return true;
    }
    return false;
  }

  // 标准化范围，移除无意义的hi值
  void _normalize() {
    if (hi != null && hi! <= low + 1) {
      hi = null;
    }
  }

  // 将整数列表转换为MsgRange数组
  static List<MsgRange>? toRanges(List<int> list) {
    if (list.isEmpty) return null;

    final sortedList = List.from(list)..sort();
    final result = <MsgRange>[];
    var current = MsgRange.id(sortedList.first);

    for (var i = 1; i < sortedList.length; i++) {
      final id = sortedList[i];
      if (!current._extend(id)) {
        current._normalize();
        result.add(current);
        current = MsgRange.id(id);
      }
    }

    result.add(current);
    return result;
  }

  // 合并可能重叠的范围为非重叠范围
  // 输入的范围数组必须已排序
  static List<MsgRange> collapse(List<MsgRange> ranges) {
    if (ranges.length <= 1) return ranges;

    final result = <MsgRange>[MsgRange.from(ranges.first)];

    for (var i = 1; i < ranges.length; i++) {
      final last = result.last;
      final current = ranges[i];

      if (last.lower == current.lower) {
        // 起始点相同，保留范围更大的
        continue;
      }

      // 检查是否有重叠
      if (last.upper >= current.lower) {
        // 有部分重叠
        if (current.upper > last.upper) {
          // 当前范围延伸得更远，扩展上一个范围
          last.hi = current.upper;
        }
        continue;
      }

      // 无重叠，直接添加
      result.add(MsgRange.from(current));
    }

    return result;
  }

  // 获取包含所有范围的最大范围，输入必须已排序
  static MsgRange? enclosing(List<MsgRange>? ranges) {
    if (ranges == null || ranges.isEmpty) return null;

    final first = MsgRange.from(ranges.first);
    if (ranges.length > 1) {
      first.hi = ranges.last.upper;
    } else {
      first.hi ??= first.upper;
    }

    return first;
  }

  // 查找非重叠范围之间的间隙，输入必须已排序且无重叠
  static List<MsgRange> gaps(List<MsgRange> ranges) {
    if (ranges.length < 2) return [];

    final gaps = <MsgRange>[];

    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i - 1].upper < ranges[i].lower) {
        // 发现间隙
        gaps.add(MsgRange.withBounds(ranges[i - 1].upper, ranges[i].lower));
      }
    }

    return gaps;
  }

  // 从源范围中裁剪掉指定范围
  static List<MsgRange> clip({required MsgRange src, required MsgRange clip}) {
    // 裁剪范围完全在源范围之外，无交集
    if (clip.upper <= src.lower || clip.lower >= src.upper) {
      return [src];
    }

    if (clip.low <= src.low) {
      if (clip.upper >= src.upper) {
        // 源范围完全在裁剪范围内，返回空
        return [];
      }
      // 部分裁剪（顶部）
      return [MsgRange.withBounds(src.lower, clip.upper)];
    }

    // 低端范围
    final lower = MsgRange.withBounds(src.lower, clip.lower);
    if (clip.upper < src.upper) {
      return [lower, MsgRange.withBounds(clip.upper, src.upper)];
    }
    return [lower];
  }

  // 用于调试和日志输出
  @override
  String toString() {
    return '[$low..$hi)';
  }

  // JSON序列化
  factory MsgRange.fromJson(Map<String, dynamic> json) =>
      _$MsgRangeFromJson(json);

  Map<String, dynamic> toJson() => _$MsgRangeToJson(this);
}
