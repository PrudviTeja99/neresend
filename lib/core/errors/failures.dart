/// Domain Failure representations for Riverpod state and UI presentation
abstract class Failure {
  final String message;
  final String? actionLabel;

  const Failure(this.message, {this.actionLabel});

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.actionLabel});
}

class SecurityFailure extends Failure {
  const SecurityFailure(super.message, {super.actionLabel});
}

class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.actionLabel});
}

class DirectLinkUnavailableFailure extends Failure {
  const DirectLinkUnavailableFailure(
    super.message, {
    super.actionLabel = 'Send Remotely',
  });
}

