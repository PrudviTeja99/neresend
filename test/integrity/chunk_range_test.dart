import 'package:flutter_test/flutter_test.dart';
import 'package:neresend/domain/models/chunk_range.dart';

void main() {
  group('ChunkRange Interval Math & Sparse Gaps Tests', () {
    test('Merges overlapping and adjacent intervals', () {
      final input = [
        const ChunkRange(0, 100),
        const ChunkRange(101, 200),
        const ChunkRange(150, 300),
        const ChunkRange(500, 600),
      ];

      final merged = ChunkRange.merge(input);
      expect(
        merged,
        equals([
          const ChunkRange(0, 300),
          const ChunkRange(500, 600),
        ]),
      );
    });

    test('Computes missing chunk ranges for hole filling', () {
      // Receiver has [0..500] and [502..2600], missing chunk is 501
      final verified = [
        const ChunkRange(0, 500),
        const ChunkRange(502, 2600),
      ];

      final missing = ChunkRange.computeMissingRanges(verified, 2601);
      expect(
        missing,
        equals([
          const ChunkRange(501, 501),
        ]),
      );
    });

    test('Computes missing ranges when nothing has been transferred yet', () {
      final missing = ChunkRange.computeMissingRanges([], 100);
      expect(missing, equals([const ChunkRange(0, 99)]));
    });

    test('Computes missing ranges with leading and trailing gaps', () {
      final verified = [
        const ChunkRange(5, 10),
        const ChunkRange(20, 25),
      ];

      final missing = ChunkRange.computeMissingRanges(verified, 30);
      expect(
        missing,
        equals([
          const ChunkRange(0, 4),
          const ChunkRange(11, 19),
          const ChunkRange(26, 29),
        ]),
      );
    });

    test('isComplete correctly identifies full range', () {
      expect(ChunkRange.isComplete([const ChunkRange(0, 99)], 100), isTrue);
      expect(
        ChunkRange.isComplete([const ChunkRange(0, 50), const ChunkRange(51, 99)], 100),
        isTrue,
      );
      expect(
        ChunkRange.isComplete([const ChunkRange(0, 50), const ChunkRange(52, 99)], 100),
        isFalse,
      );
    });
  });
}
