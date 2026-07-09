import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../state/voice_provider.dart';
import '../theme/ambient.dart';

/// Voice/command sheet: speak (where the platform has STT — Android, iOS,
/// macOS) or type a natural-language command. Same intent engine either way.
class VoiceSheet extends ConsumerStatefulWidget {
  const VoiceSheet({super.key});

  @override
  ConsumerState<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<VoiceSheet> {
  final _inputCtrl = TextEditingController();
  final _speech = SpeechToText();
  bool _sttAvailable = false;
  bool _listening = false;
  String? _response;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initStt();
  }

  Future<void> _initStt() async {
    try {
      final ok = await _speech.initialize();
      if (mounted) setState(() => _sttAvailable = ok);
    } catch (_) {
      // no STT backend on this platform (e.g. Windows) — typing still works
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _inputCtrl.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _listening = false);
          _run();
        }
      },
    );
  }

  Future<void> _run() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty || _busy) return;
    setState(() => _busy = true);
    final response = await ref.read(voiceExecutorProvider)(input);
    if (!mounted) return;
    setState(() {
      _response = response;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What should happen?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'e.g. "turn on the kitchen light" · "set thermostat to 21" · '
            '"dim hue go to 30" · "run scene evening"',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Type a command…',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _run(),
                ),
              ),
              if (_sttAvailable) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                  color: _listening ? Ambient.accent : null,
                  tooltip: _listening ? 'Stop listening' : 'Speak',
                  onPressed: _listen,
                ),
              ],
              const SizedBox(width: 8),
              IconButton.filled(
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                tooltip: 'Run',
                onPressed: _run,
              ),
            ],
          ),
          if (_response != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_response!)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
