import 'dart:math' as math;

/// Represents an inclusive chunk index interval [start, end] for sparse resumption
class ChunkRange {
  final int start;
  final int end; // Inclusive

  const ChunkRange(this.start, this.end) : assert(start <= end, 'start must be <= end');

  int get count => end - start + 1;

  bool contains(int chunkIndex) => chunkIndex >= start && chunkIndex <= end;

  List<int> toList() => [start, end];

  factory ChunkRange.fromList(List<dynamic> list) {
    if (list.length != 2) {
      throw const FormatException('ChunkRange requires exactly [start, end]');
    }
    return ChunkRange(list[0] as int, list[1] as int);
  }

  /// Merges overlapping and contiguous chunk intervals into canonical disjoint intervals
  static List<ChunkRange> merge(List<ChunkRange> ranges) {
    if (ranges.isEmpty) return [];
    final sorted = List<ChunkRange>.from(ranges)..sort((a, b) => a.start.compareTo(b.start));
    final merged = <ChunkRange>[sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final current = sorted[i];
      final last = merged.last;
      if (current.start <= last.end + 1) {
        merged[merged.length - 1] = ChunkRange(last.start, math.max(last.end, current.end));
      } else {
        merged.add(current);
      }
    }
    return merged;
  }

  /// Calculates total verified chunk count from a list of disjoint ranges
  static int totalVerifiedChunks(List<ChunkRange> ranges) {
    return ranges.fold(0, (sum, r) => sum + r.count);
  }

  /// Returns true if all chunks from 0 to totalChunks - 1 are verified
  static bool isComplete(List<ChunkRange> ranges, int totalChunks) {
    if (totalChunks <= 0) return true;
    final merged = merge(ranges);
    return merged.length == 1 && merged.first.start == 0 && merged.first.end == totalChunks - 1;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChunkRange && runtimeType == other.runtimeType && start == other.start && end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;

  @override
  String toString() => '[$start..$end]';
}

