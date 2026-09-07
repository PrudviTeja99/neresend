import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neresend/data/transports/webrtc/remote_signaling_client.dart';
import 'package:neresend/presentation/screens/remote_tab_screen.dart';
import 'package:neresend/presentation/state/orchestrator_provider.dart';
import 'package:neresend/data/services/transfer_orchestrator.dart';

class FakeTransferOrchestrator implements TransferOrchestrator {
  int sessionCreationCount = 0;
  RemoteSessionInfo? activeSession;

  @override
  RemoteSessionInfo? get activeRemoteSession => activeSession;

  @override
  Future<RemoteSessionInfo> startRemoteHostSession({
    String? preferredPin,
    bool forceNew = false,
  }) async {
    sessionCreationCount++;
    final info = RemoteSessionInfo(
      sessionId: 'sess_$sessionCreationCount',
      authToken: 'token_$sessionCreationCount',
      pin: '777 88$sessionCreationCount',
      inviteUri: 'neresend://pair?session=sess_$sessionCreationCount&pin=77788$sessionCreationCount',
      createdAt: DateTime.now(),
      ttl: const Duration(minutes: 5),
    );
    activeSession = info;
    return info;
  }

  @override
  Future<void> disposeActiveRemoteHostSession() async {
    activeSession = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RemoteTabScreen Lifecycle & State Tests', () {
    testWidgets('Displays loading state while orchestrator provider is loading',
        (tester) async {
      final completer = Completer<TransferOrchestrator>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferOrchestratorProvider.overrideWith((ref) => completer.future),
          ],
          child: const MaterialApp(
            home: Scaffold(body: RemoteTabScreen()),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Initializing secure transfer engine...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Displays error state and retry button on provider error',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferOrchestratorProvider.overrideWith(
                (ref) => Future.error('Network interface unavailable')),
          ],
          child: const MaterialApp(
            home: Scaffold(body: RemoteTabScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('Initialization Error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
        'Automatically creates remote session and starts countdown when provider is ready',
        (tester) async {
      final fakeOrchestrator = FakeTransferOrchestrator();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferOrchestratorProvider.overrideWith(
                (ref) => Future.value(fakeOrchestrator)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: RemoteTabScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(fakeOrchestrator.sessionCreationCount, 1);
      expect(find.text('777 881'), findsOneWidget);
      expect(find.textContaining('Expires in 05:00'), findsOneWidget);
      expect(find.text('New PIN'), findsOneWidget);

      // Advance clock by 1 second to test timer countdown
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Expires in 04:59'), findsOneWidget);
    });

    testWidgets(
        'New PIN button regenerates session sequentially and updates display',
        (tester) async {
      final fakeOrchestrator = FakeTransferOrchestrator();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferOrchestratorProvider.overrideWith(
                (ref) => Future.value(fakeOrchestrator)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: RemoteTabScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('777 881'), findsOneWidget);

      // Click "New PIN"
      await tester.tap(find.text('New PIN'));
      await tester.pumpAndSettle();

      expect(fakeOrchestrator.sessionCreationCount, 2);
      expect(find.text('777 882'), findsOneWidget);
      expect(find.textContaining('Expires in 05:00'), findsOneWidget);
    });
  });
}
