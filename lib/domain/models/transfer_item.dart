/// Represents a single file entry within a transfer manifest
class TransferItem {
  final String id;
  final String fileName;
  final int size;
  final String mimeType;
  final String wholeFileSha256;
  final int chunkSize;
  final int totalChunks;
  final List<String> chunkHashes; // SHA-256 hash per chunk

  const TransferItem({
    required this.id,
    required this.fileName,
    required this.size,
    required this.mimeType,
    required this.wholeFileSha256,
    required this.chunkSize,
    required this.totalChunks,
    required this.chunkHashes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'size': size,
    'mimeType': mimeType,
    'wholeFileSha256': wholeFileSha256,
    'chunkSize': chunkSize,
    'totalChunks': totalChunks,
    'chunkHashes': chunkHashes,
  };

  factory TransferItem.fromJson(Map<String, dynamic> json) {
    return TransferItem(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      size: json['size'] as int,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      wholeFileSha256: json['wholeFileSha256'] as String,
      chunkSize: json['chunkSize'] as int,
      totalChunks: json['totalChunks'] as int,
      chunkHashes: (json['chunkHashes'] as List<dynamic>).cast<String>(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          wholeFileSha256 == other.wholeFileSha256;

  @override
  int get hashCode => id.hashCode ^ wholeFileSha256.hashCode;
}

