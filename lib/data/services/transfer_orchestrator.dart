import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../../core/constants/protocol_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../domain/contracts/neresend_transport.dart';
import '../../domain/contracts/transfer_protocol_engine.dart';
import '../../domain/models/device_identity.dart';
import '../../domain/models/discovered_peer.dart';
import '../../domain/models/transfer_mode.dart';
import '../../domain/models/transfer_progress.dart';
import '../discovery/ble_discovery_driver.dart';
import '../discovery/lan_discovery_driver.dart';
import '../discovery/remote_discovery_driver.dart';
import '../protocol/neresend_protocol_engine.dart';
import '../transports/direct_link/direct_link_factory.dart';
import '../transports/local_tls/local_tls_client.dart';
import '../transports/local_tls/local_tls_server.dart';
import '../transports/webrtc/webrtc_connection_manager.dart';
import 'identity_service.dart';
import 'power_management_service.dart';
import 'storage_service.dart';

/// Prompt payload emitted to presentation layer when an incoming transfer requires user confirmation
class IncomingTransferPrompt {
  final IncomingTransferRequest request;
  final String senderAlias;
  final String senderFingerprint;
  final int totalFiles;
  final int totalBytes;
  final String sasEmojis;
  final bool isRemote;

  const IncomingTransferPrompt({
    required this.request,
    required this.senderAlias,
    required this.senderFingerprint,
    required this.totalFiles,
    required this.totalBytes,
    this.sasEmojis = '',
    this.isRemote = false,
  });
}

/// Central controller coordinating discovery drivers, transport adapters, protocol engine, and storage
class TransferOrchestrator {
  final IdentityService identityService;
  final DeviceIdentity localIdentity;
  final StorageService storageService;
  final PowerManagementService powerService;

  late final LanDiscoveryDriver lanDiscovery;
  late final BleDiscoveryDriver bleDiscovery;
  late final RemoteDiscoveryDriver remoteDiscovery;

  late final LocalTlsServer localTlsServer;
  late final LocalTlsClient localTlsClient;
  late final WebRtcConnectionManager webrtcManager;
  late final NeReSendProtocolEngine protocolEngine;

  final Map<String, DiscoveredPeer> _aggregatedPeers = {};
  final StreamController<List<DiscoveredPeer>> _peersController =
      StreamController<List<DiscoveredPeer>>.broadcast();

  final StreamController<IncomingTransferPrompt> _promptController =
      StreamController<IncomingTransferPrompt>.broadcast();

  StreamSubscription<List<DiscoveredPeer>>? _lanSub;
  StreamSubscription<List<DiscoveredPeer>>? _bleSub;
  StreamSubscription<List<DiscoveredPeer>>? _remoteSub;
  StreamSubscription<IncomingTransferRequest>? _incomingRequestSub;
  StreamSubscription<TransferProgress>? _progressSub;

  bool _initialized = false;
  bool _isListening = false;
  int _tlsPort = 53318;

  TransferOrchestrator({
    required this.identityService,
    required this.localIdentity,
    required this.storageService,
    PowerManagementService? powerService,
    int tlsPort = 53318,
  })  : powerService = powerService ?? PowerManagementService(),
        _tlsPort = tlsPort {
    lanDiscovery =
        LanDiscoveryDriver(localIdentity: localIdentity, tcpPort: _tlsPort);
    bleDiscovery =
        BleDiscoveryDriver(localIdentity: localIdentity, tcpPort: _tlsPort);
    remoteDiscovery = RemoteDiscoveryDriver(localIdentity: localIdentity);

    localTlsServer = LocalTlsServer(
      identityService: identityService,
      localIdentity: localIdentity,
    );

    localTlsClient = LocalTlsClient(
      identityService: identityService,
      localIdentity: localIdentity,
    );

    webrtcManager = WebRtcConnectionManager();
    protocolEngine = NeReSendProtocolEngine(localIdentity: localIdentity);
  }

  Stream<List<DiscoveredPeer>> get onPeersChanged => _peersController.stream;
  Stream<IncomingTransferPrompt> get onIncomingTransferPrompt =>
      _promptController.stream;
  Stream<TransferProgress> get onProgress => protocolEngine.onProgress;
  List<DiscoveredPeer> get currentPeers => _aggregatedPeers.values.toList();
  bool get isReady => _isListening;

  /// Start all listeners, discovery drivers, and storage service
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await storageService.init();

    // 1. Start TLS server
    try {
      await localTlsServer.startListening(_tlsPort);
      _isListening = true;
      localTlsServer.onIncomingTransport.listen((transport) {
        protocolEngine.listenToTransport(transport);
      });
    } catch (_) {
      _isListening = false;
    }

    // 2. Start Discovery Drivers
    await lanDiscovery.startDiscovery();
    await bleDiscovery.startDiscovery();

    _lanSub = lanDiscovery.onPeersChanged.listen((peers) => _updatePeers());
    _bleSub = bleDiscovery.onPeersChanged.listen((peers) => _updatePeers());
    _remoteSub =
        remoteDiscovery.onPeersChanged.listen((peers) => _updatePeers());

    // 3. Listen for incoming transfer requests from protocol engine
    _incomingRequestSub =
        protocolEngine.onIncomingRequest.listen(_handleIncomingTransferRequest);

    // 4. Track active transfer progress for history and power locks
    _progressSub = protocolEngine.onProgress.listen((progress) {
      if (progress.status == TransferStatus.transferring) {
        powerService.acquireTransferLocks(progress.transferId);
      } else if (progress.isTerminated) {
        powerService.releaseTransferLocks(progress.transferId);
      }
    });
  }

  void _updatePeers() {
    final combined = <String, DiscoveredPeer>{};

    for (final peer in lanDiscovery.currentPeers) {
      combined[peer.fingerprint] = peer;
    }
    for (final peer in bleDiscovery.currentPeers) {
      combined[peer.fingerprint] = peer;
    }
    for (final peer in remoteDiscovery.currentPeers) {
      combined[peer.fingerprint] = peer;
    }

    _aggregatedPeers.clear();
    _aggregatedPeers.addAll(combined);

    if (!_peersController.isClosed) {
      _peersController.add(_aggregatedPeers.values.toList());
    }
  }

  /// Send files to a discovered peer
  Future<void> sendFiles(DiscoveredPeer peer, List<File> files) async {
    if (files.isEmpty) return;

    NeReSendTransport transport;

    if (peer.supportedMode == TransferMode.lan) {
      // Connect over TLS 1.3 socket
      transport = await localTlsClient.connectToPeer(
        host: peer.ipAddress,
        port: peer.port,
        expectedFingerprint: peer.fingerprint,
      );
    } else if (peer.supportedMode == TransferMode.direct) {
      // Direct Link connection
      final adapter = DirectLinkFactory.createPlatformAdapter();
      final caps = await adapter.checkCapabilities();
      if (!caps.canConnect) {
        throw const DirectLinkUnavailableException(
            'Device cannot establish Direct Link connection');
      }
      transport = await localTlsClient.connectToPeer(
        host: peer.ipAddress,
        port: peer.port,
        expectedFingerprint: peer.fingerprint,
      );
    } else {
      throw const NetworkException(
          'Remote transfer requires PIN session setup via Remote tab');
    }

    final totalBytes = files.fold<int>(
        0, (sum, f) => sum + (f.existsSync() ? f.lengthSync() : 0));

    // Record in history
    await storageService.addHistoryEntry(
      TransferHistoryEntry(
        id: const Uuid().v4(),
        transferId: const Uuid().v4(),
        fileName: files.length == 1
            ? files.first.path.split('/').last
            : '${files.length} files',
        totalBytes: totalBytes,
        isSender: true,
        peerAlias: peer.alias,
        peerFingerprint: peer.fingerprint,
        timestamp: DateTime.now(),
        status: 'sending',
      ),
    );

    await protocolEngine.startSenderSession(transport, files);
  }

  Future<void> _handleIncomingTransferRequest(
      IncomingTransferRequest request) async {
    final manifest = request.manifest;
    final senderFp = manifest.senderFingerprint;

    // Check disk space
    final downloadDir = await storageService.getDefaultDownloadDirectory();
    final freeSpace =
        await storageService.getAvailableDiskSpace(downloadDir.path);

    if (manifest.totalBytes > freeSpace) {
      await protocolEngine.declineTransfer(
        manifest.transferId,
        reason: ProtocolConstants.declineInsufficientStorage,
      );
      return;
    }

    // Check if device is trusted (Auto-Accept)
    final isTrusted = await identityService.isTrusted(senderFp);
    if (isTrusted) {
      await acceptTransfer(manifest.transferId);
      return;
    }

    // Prompt user for confirmation (Trust On First Use)
    _promptController.add(
      IncomingTransferPrompt(
        request: request,
        senderAlias: manifest.senderAlias,
        senderFingerprint: manifest.senderFingerprint,
        totalFiles: manifest.totalFiles,
        totalBytes: manifest.totalBytes,
      ),
    );
  }

  /// Accept incoming transfer
  Future<void> acceptTransfer(String transferId,
      {bool rememberDevice = false, String? senderFingerprint}) async {
    if (rememberDevice && senderFingerprint != null) {
      await identityService.pinTrustedDevice(senderFingerprint);
    }

    final downloadDir = await storageService.getDefaultDownloadDirectory();
    await protocolEngine.acceptTransfer(transferId, downloadDir.path);
  }

  /// Decline incoming transfer
  Future<void> declineTransfer(String transferId,
      {String reason = ProtocolConstants.declineUserRejected}) async {
    await protocolEngine.declineTransfer(transferId, reason: reason);
  }

  /// Pause active transfer
  Future<void> pauseTransfer(String transferId) async {
    await protocolEngine.pauseTransfer(transferId);
  }

  /// Resume active transfer
  Future<void> resumeTransfer(String transferId) async {
    await protocolEngine.resumeTransfer(transferId);
  }

  /// Cancel active transfer
  Future<void> cancelTransfer(String transferId) async {
    await protocolEngine.cancelTransfer(transferId);
  }

  Future<void> dispose() async {
    await _lanSub?.cancel();
    await _bleSub?.cancel();
    await _remoteSub?.cancel();
    await _incomingRequestSub?.cancel();
    await _progressSub?.cancel();

    await lanDiscovery.dispose();
    await bleDiscovery.dispose();
    await remoteDiscovery.dispose();
    await localTlsServer.dispose();

    protocolEngine.dispose();
    powerService.releaseAll();

    await _peersController.close();
    await _promptController.close();
  }
}
