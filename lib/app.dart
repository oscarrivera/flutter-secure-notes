import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'application/lock_service.dart';
import 'application/notes_service.dart';
import 'domain/repositories.dart';
import 'infrastructure/encrypted_notes_store.dart';
import 'infrastructure/secure_key_store.dart';
import 'presentation/lock_screen.dart';
import 'presentation/notes_list_page.dart';

class AppContainer {
  AppContainer({required this.lock, required this.notes});

  final LockService lock;
  final NotesService notes;

  /// Production: DEK and PIN hash in platform secure storage.
  static Future<AppContainer> production() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    );
    final keys = DelegatingSecureKeyStore(
      read: (k) => storage.read(key: k),
      write: (k, v) => storage.write(key: k, value: v),
      delete: (k) => storage.delete(key: k),
    );
    final dir = await getApplicationDocumentsDirectory();
    final lock = LockService(
      keys: keys,
      clock: const SystemClock(),
    );
    final notes = NotesService(
      store: EncryptedNotesStore(
        records: FileStringStore(File('${dir.path}/notes_v1.json')),
      ),
      lock: lock,
    );
    return AppContainer(lock: lock, notes: notes);
  }

  /// Tests / platforms without Keystore: in-memory fake.
  factory AppContainer.inMemory() {
    final lock = LockService(
      keys: InMemorySecureKeyStore(),
      clock: const SystemClock(),
    );
    final notes = NotesService(
      store: EncryptedNotesStore(records: InMemoryStringStore()),
      lock: lock,
    );
    return AppContainer(lock: lock, notes: notes);
  }
}

class SecureNotesApp extends StatelessWidget {
  const SecureNotesApp({super.key, required this.container});

  final AppContainer container;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notas cifradas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4D3E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: RootGate(container: container),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key, required this.container});

  final AppContainer container;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  late Future<bool> _hasPin;
  Timer? _idleTick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hasPin = widget.container.lock.hasPin();
    _idleTick = Timer.periodic(const Duration(seconds: 5), (_) => _onIdleTick());
  }

  @override
  void dispose() {
    _idleTick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onIdleTick();
    }
  }

  void _onIdleTick() {
    final lock = widget.container.lock;
    final wasUnlocked = lock.isUnlocked;
    lock.lockIfIdle();
    if (wasUnlocked && !lock.isUnlocked && mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      setState(() {});
    }
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => widget.container.lock.recordActivity(),
      child: FutureBuilder<bool>(
        future: _hasPin,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final lock = widget.container.lock;
          if (!snap.data!) {
            return LockScreen(
              lock: lock,
              mode: LockMode.setup,
              onUnlocked: () {
                _hasPin = Future<bool>.value(true);
                _refresh();
              },
            );
          }
          if (!lock.isUnlocked) {
            return LockScreen(
              lock: lock,
              mode: LockMode.unlock,
              onUnlocked: _refresh,
            );
          }
          return NotesListPage(
            notes: widget.container.notes,
            lock: lock,
            onLock: _refresh,
          );
        },
      ),
    );
  }
}
