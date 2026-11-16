import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class TorrServerService {
  static const MethodChannel _channel = MethodChannel('com.chiavegatti.cinema/torrserver');
  static const String baseUrl = 'http://127.0.0.1:8090';
  static Process? _processo;
  static bool _iniciando = false;

  static Future<bool> estaAtivo() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/echo'))
          .timeout(const Duration(milliseconds: 1200));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> garantirAtivo() async {
    if (await estaAtivo()) return true;
    if (_iniciando) {
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (await estaAtivo()) return true;
      }
      return false;
    }

    if (!Platform.isAndroid) return false;
    _iniciando = true;
    try {
      final info = await _channel.invokeMapMethod<String, String>('getPaths');
      final nativeDir = info?['nativeLibDir'] ?? '';
      final filesDir = info?['filesDir'] ?? '';
      if (nativeDir.isEmpty) return false;

      final binPath = '$nativeDir/libtorrserver.so';
      final binFile = File(binPath);
      if (!await binFile.exists()) return false;

      final dataDir = Directory('$filesDir/torrserver');
      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
      }

      _processo = await Process.start(
        binPath,
        ['-p', '8090', '-d', dataDir.path, '-r'],
        mode: ProcessStartMode.detachedWithStdio,
      );

      for (int i = 0; i < 12; i++) {
        await Future.delayed(const Duration(milliseconds: 400));
        if (await estaAtivo()) return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _iniciando = false;
    }
  }
}
