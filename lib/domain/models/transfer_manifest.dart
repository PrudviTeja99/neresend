import 'transfer_item.dart';

/// Comprehensive transfer metadata and file list
class TransferManifest {
  final String transferId;
  final String senderAlias;
  final String senderFingerprint;
  final List<TransferItem> files;
  final int totalBytes;
  final int totalFiles;
  final DateTime createdAt;

  const TransferManifest({
    required this.transferId,
    required this.senderAlias,
    required this.senderFingerprint,
    required this.files,
    required this.totalBytes,
    required this.totalFiles,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'transferId': transferId,
    'senderAlias': senderAlias,
    'senderFingerprint': senderFingerprint,
    'files': files.map((f) => f.toJson()).toList(),
    'totalBytes': totalBytes,
    'totalFiles': totalFiles,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TransferManifest.fromJson(Map<String, dynamic> json) {
    return TransferManifest(
      transferId: json['transferId'] as String,
      senderAlias: json['senderAlias'] as String,
      senderFingerprint: json['senderFingerprint'] as String,
      files: (json['files'] as List<dynamic>)
          .map((f) => TransferItem.fromJson(f as Map<String, dynamic>))
          .toList(),
      totalBytes: json['totalBytes'] as int,
      totalFiles: json['totalFiles'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferManifest &&
          runtimeType == other.runtimeType &&
          transferId == other.transferId;

  @override
  int get hashCode => transferId.hashCode;
}

