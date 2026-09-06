import 'dart:io';

/// Port for file system interactions, directory selection, and disk space validation
abstract class StorageRepository {
  /// Gets the default downloads directory for DropFlow
  Future<Directory> getDefaultDownloadDirectory();

  /// Gets free disk space in bytes for the given directory path
  Future<int> getAvailableDiskSpace(String directoryPath);

  /// Sanitizes incoming filename against path traversal attacks and OS reserved chars
  String sanitizeFilename(String rawFilename);

  /// Resolves a safe file destination, appending numeric suffixes (e.g. "file (1).txt") if name exists
  Future<File> resolveDestinationFile(String directoryPath, String sanitizedFilename);
}

