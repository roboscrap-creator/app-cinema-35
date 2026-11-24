import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CdnResolucaoInfo {
  final String url;
  final String origem;
  final int latenciaMs;

  const CdnResolucaoInfo({
    required this.url,
    required this.origem,
    required this.latenciaMs,
  });
}

class _CacheEntry {
  final String url;
  final String origemBackend;
  final DateTime expiraEm;

  _CacheEntry({
    required this.url,
    required this.origemBackend,
    required this.expiraEm,
  });
}

class CdnStreamService {
  static const String _endpoint =
      'https://roboscrap-backend-l9t8.onrender.com/stream-torbox';
  static final Map<String, _CacheEntry> _cache = {};
  static final Map<String, Future<String?>> _emAndamento = {};

  static String? ultimoDiagnostico;

  static String _chaveMagnet(String magnet) {
    final m = RegExp(r'btih:([a-zA-Z0-9]{32,40})', caseSensitive: false)
        .firstMatch(magnet);
    return (m?.group(1) ?? magnet.trim()).toLowerCase();
  }

  static void invalidarCache(String magnet) { _cache.remove(_chaveMagnet(magnet)); }

  static void preAquecerMagnet(String? url) {
    if (url == null) return;
    final clean = url.trim();
    if (!clean.toLowerCase().startsWith('magnet:?xt=urn:btih:')) return;
    final chave = _chaveMagnet(clean);
    final hit = _cache[chave];
    if (hit != null && hit.expiraEm.isAfter(DateTime.now())) return;
    if (_emAndamento.containsKey(chave)) return;
    _requisitarCdn(clean, chave);
  }

  static Future<CdnResolucaoInfo?> resolverMagnet(String magnet) async {
    final clean = magnet.trim();
    if (!clean.toLowerCase().startsWith('magnet:?xt=urn:btih:')) return null;
    final chave = _chaveMagnet(clean);
    final sw = Stopwatch()..start();

    final hit = _cache[chave];
    if (hit != null && hit.expiraEm.isAfter(DateTime.now())) {
      sw.stop();
      final diag =
          'Origem: Gcore CDN (Pré-carregado • ${hit.origemBackend}) | ${sw.elapsedMilliseconds}ms';
      ultimoDiagnostico = diag;
      return CdnResolucaoInfo(
        url: hit.url,
        origem: diag,
        latenciaMs: sw.elapsedMilliseconds,
      );
    }

    final urlResolvida = await (_emAndamento[chave] ?? _requisitarCdn(clean, chave));
    sw.stop();
    if (urlResolvida != null && urlResolvida.isNotEmpty) {
      final host = Uri.tryParse(urlResolvida)?.host ?? 'Gcore CDN';
      final diag =
          'Origem: Gcore CDN ($host) | ${sw.elapsedMilliseconds}ms';
      ultimoDiagnostico = diag;
      return CdnResolucaoInfo(
        url: urlResolvida,
        origem: diag,
        latenciaMs: sw.elapsedMilliseconds,
      );
    }
    return null;
  }

  static Future<String?> _requisitarCdn(String magnet, String chave) {
    final fut = () async {
      try {
        final res = await http
            .post(
              Uri.parse(_endpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'magnet': magnet}),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final u = (data is Map ? data['url'] : null)?.toString().trim() ?? '';
          final src =
              (data is Map ? data['source'] : null)?.toString() ?? 'torbox';
          if (u.startsWith('http://') || u.startsWith('https://')) {
            if (_cache.length > 80) { _cache.remove(_cache.keys.first); }
      _cache[chave] = _CacheEntry(
              url: u,
              origemBackend: src,
              expiraEm: DateTime.now().add(const Duration(hours: 3, minutes: 30)),
            );
            return u;
          }
        }
      } catch (_) {}
      return null;
    }();

    _emAndamento[chave] = fut;
    fut.whenComplete(() => _emAndamento.remove(chave));
    return fut;
  }
}
