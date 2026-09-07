import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/lock_service.dart';
import '../domain/failures.dart';

enum LockMode { setup, unlock }

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.lock,
    required this.mode,
    required this.onUnlocked,
  });

  final LockService lock;
  final LockMode mode;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.lock.lockoutRemaining() != null && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pin.text.trim();
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (widget.mode == LockMode.setup) {
        if (pin != _confirm.text.trim()) {
          setState(() => _error = 'Los PIN no coinciden.');
          return;
        }
        await widget.lock.setInitialPin(pin);
      } else {
        await widget.lock.unlock(pin);
      }
      widget.onUnlocked();
    } on AppFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.mode == LockMode.setup;
    final remaining = widget.lock.lockoutRemaining();
    final lockedOut = remaining != null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Icon(
                Icons.lock_outline,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Notas cifradas',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                setup
                    ? 'Crea un PIN de 6 dígitos. No hay recuperación.'
                    : 'Introduce el PIN para desbloquear.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pin,
                enabled: !lockedOut && !_busy,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  if (!setup) {
                    unawaited(_submit());
                  }
                },
              ),
              if (setup) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Repite el PIN',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => unawaited(_submit()),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (lockedOut) ...[
                const SizedBox(height: 12),
                Text(
                  'Bloqueado ${remaining.inSeconds} s.',
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _busy || lockedOut ? null : () => unawaited(_submit()),
                child: Text(setup ? 'Guardar PIN' : 'Desbloquear'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
