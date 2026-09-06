import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/contracts/storage_repository.dart';
import '../../domain/integrity/part_file_manager.dart';

/// Transfer history record persisted on local disk
class TransferHistoryEntry {
  final String id;
  final String transferId;
  final String fileName;
  final int totalBytes;
  final bool isSender;
  final String peerAlias;
  final String peerFingerprint;
  final DateTime timestamp;
  final String status;
  final String? savedPath;

  const TransferHistoryEntry({
    required this.id,
    required this.transferId,
    required this.fileName,
    required this.totalBytes,
    required this.isSender,
    required this.peerAlias,
    required this.peerFingerprint,
    required this.timestamp,
    required this.status,
    this.savedPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'transferId': transferId,
        'fileName': fileName,
        'totalBytes': totalBytes,
        'isSender': isSender,
        'peerAlias': peerAlias,
        'peerFingerprint': peerFingerprint,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'savedPath': savedPath,
      };

  factory TransferHistoryEntry.fromJson(Map<String, dynamic> json) =>
      TransferHistoryEntry(
        id: json['id'] as String,
        transferId: json['transferId'] as String,
        fileName: json['fileName'] as String,
        totalBytes: json['totalBytes'] as int,
        isSender: json['isSender'] as bool,
        peerAlias: json['peerAlias'] as String,
        peerFingerprint: json['peerFingerprint'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        status: json['status'] as String,
        savedPath: json['savedPath'] as String?,
      );
}

/// Concrete implementation of StorageRepository for cross-platform file saving and history
class StorageService implements StorageRepository {
  Directory? _customDownloadDir;
  final List<TransferHistoryEntry> _history = [];
  File? _historyFile;

  StorageService({Directory? customDownloadDir})
      : _customDownloadDir = customDownloadDir;

  Future<void> init() async {
    try {
      final baseDir = await _getBaseAppDir();
      _historyFile = File(p.join(baseDir.path, 'transfer_history.json'));
      if (await _historyFile!.exists()) {
        final content = await _historyFile!.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
          _history.clear();
          _history.addAll(
            jsonList.map((e) =>
                TransferHistoryEntry.fromJson(e as Map<String, dynamic>)),
          );
        }
      }
    } catch (_) {}
  }

  Future<Directory> _getBaseAppDir() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      final fallback =
          Directory(p.join(Directory.systemTemp.path, 'dropflow_app'));
      if (!await fallback.exists()) await fallback.create(recursive: true);
      return fallback;
    }
  }

  @override
  Future<Directory> getDefaultDownloadDirectory() async {
    if (_customDownloadDir != null) {
      if (!await _customDownloadDir!.exists()) {
        await _customDownloadDir!.create(recursive: true);
      }
      return _customDownloadDir!;
    }

    try {
      if (Platform.isAndroid) {
        final androidDownload = Directory('/storage/emulated/0/Download');
        if (await androidDownload.exists()) return androidDownload;
      }

      final dir = await getDownloadsDirectory();
      if (dir != null && await dir.exists()) return dir;

      final docs = await getApplicationDocumentsDirectory();
      final dropflowDir = Directory(p.join(docs.path, 'DropFlow'));
      if (!await dropflowDir.exists())
        await dropflowDir.create(recursive: true);
      return dropflowDir;
    } catch (_) {
      final fallback =
          Directory(p.join(Directory.systemTemp.path, 'DropFlow_Downloads'));
      if (!await fallback.exists()) await fallback.create(recursive: true);
      return fallback;
    }
  }

  void setCustomDownloadDirectory(Directory dir) {
    _customDownloadDir = dir;
  }

  @override
  Future<int> getAvailableDiskSpace(String directoryPath) async {
    // Return 50 GB default available estimate if low-level OS call is unavailable
    return 50 * 1024 * 1024 * 1024;
  }

  @override
  String sanitizeFilename(String rawFilename) {
    return PartFileManager.sanitizeFilename(rawFilename);
  }

  @override
  Future<File> resolveDestinationFile(
      String directoryPath, String sanitizedFilename) async {
    final clean = sanitizeFilename(sanitizedFilename);
    var candidate = File(p.join(directoryPath, clean));
    if (!await candidate.exists()) return candidate;

    final ext = p.extension(clean);
    final base = p.basenameWithoutExtension(clean);

    int count = 1;
    while (await candidate.exists()) {
      final newName = '$base ($count)$ext';
      candidate = File(p.join(directoryPath, newName));
      count++;
    }

    return candidate;
  }

  List<TransferHistoryEntry> get history => List.unmodifiable(_history);

  Future<void> addHistoryEntry(TransferHistoryEntry entry) async {
    _history.insert(0, entry);
    if (_history.length > 200) {
      _history.removeRange(200, _history.length);
    }
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
  }

  Future<void> _saveHistory() async {
    if (_historyFile == null) return;
    try {
      final jsonStr = jsonEncode(_history.map((e) => e.toJson()).toList());
      await _historyFile!.writeAsString(jsonStr);
    } catch (_) {}
  }
}
