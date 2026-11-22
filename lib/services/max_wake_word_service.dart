import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import '../main.dart';
import 'max_assistant_service.dart';
import 'max_memory_service.dart';

class MaxWakeWordService {
  static final MaxWakeWordService instance = MaxWakeWordService._();
  MaxWakeWordService._();

  final SpeechToText _stt = SpeechToText();
  bool _ativo = false;
  bool _pausado = false;
  bool _escutandoLoop = false;
  bool _disponivel = false;
  Timer? _restartTimer;
  void Function(String? comandoDireto)? _onAcordar;

  Future<void> iniciar({required void Function(String? comandoDireto) onAcordar}) async {
    _onAcordar = onAcordar;
    if (_ativo) return;
    _ativo = true;
    _pausado = false;
    try {
      _disponivel = await _stt.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            _escutandoLoop = false;
            _agendarReiniciar();
          }
        },
        onError: (_) {
          _escutandoLoop = false;
          _agendarReiniciar(segundos: 3);
        },
      );
      if (_disponivel) _ouvirAgora();
    } catch (_) {
      _disponivel = false;
    }
  }

  void pausar() {
    _pausado = true;
    _restartTimer?.cancel();
    if (_escutandoLoop) {
      _escutandoLoop = false;
      _stt.stop();
    }
  }

  void retomar() {
    if (!_ativo) return;
    _pausado = false;
    _agendarReiniciar(segundos: 1);
  }

  void _agendarReiniciar({int segundos = 1}) {
    _restartTimer?.cancel();
    if (!_ativo || _pausado || !_disponivel) return;
    _restartTimer = Timer(Duration(seconds: segundos), _ouvirAgora);
  }

  Future<void> _ouvirAgora() async {
    if (!_ativo || _pausado || !_disponivel || _escutandoLoop) return;
    if (CinemaOrientation.emPlayer) {
      _agendarReiniciar(segundos: 3);
      return;
    }
    final max = MaxAssistantService.instance;
    if (max.ouvindo || max.falando || max.processando) {
      _agendarReiniciar(segundos: 2);
      return;
    }

    try {
      _escutandoLoop = true;
      await _stt.listen(
        localeId: 'pt_BR',
        listenMode: ListenMode.dictation,
        partialResults: true,
        listenFor: const Duration(seconds: 25),
        pauseFor: const Duration(seconds: 4),
        onResult: (res) {
          final txt = res.recognizedWords.trim();
          if (txt.isEmpty) return;
          final rx = RegExp(r'\b(?:oi\s+|ol[aá]\s+|ei\s+)?max\b[\s,!?]*(.*)', caseSensitive: false);
          final m = rx.firstMatch(txt);
          if (m != null) {
            final resto = (m.group(1) ?? '').trim();
            _escutandoLoop = false;
            _stt.stop();
            if (resto.length >= 3 && res.finalResult) {
              _onAcordar?.call(resto);
            } else if (resto.isEmpty || res.finalResult) {
              final nome = MaxMemoryService.instance.nomeAtual;
              final saudacao = (nome.isNotEmpty && nome.toLowerCase() != 'geral')
                  ? 'Oi $nome, estou aqui! Pode falar.'
                  : 'Oi, estou aqui! Pode falar.';
              MaxAssistantService.instance.falar(saudacao);
              _onAcordar?.call(resto.length >= 3 ? resto : null);
            }
          }
        },
      );
    } catch (_) {
      _escutandoLoop = false;
      _agendarReiniciar(segundos: 4);
    }
  }
}
