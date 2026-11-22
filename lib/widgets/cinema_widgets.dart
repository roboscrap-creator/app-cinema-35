import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/midia_model.dart';

class CinemaLogoWidget extends StatelessWidget {
  final double height;
  final double width;

  const CinemaLogoWidget({
    super.key,
    this.height = 38,
    this.width = 132,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1D26),
            Color(0xFF0E1016),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: height * 0.56,
            decoration: BoxDecoration(
              color: const Color(0xFFF5B82E),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Cinema',
            style: TextStyle(
              color: Colors.white,
              fontSize: height * 0.54,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class TopIconeComTooltip extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const TopIconeComTooltip({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  State<TopIconeComTooltip> createState() => _TopIconeComTooltipState();
}

class _TopIconeComTooltipState extends State<TopIconeComTooltip> {
  bool _focado = false;
  bool _mostrarHint = false;
  Timer? _timer;

  void _ativarHintTemporario() {
    _timer?.cancel();
    setState(() => _mostrarHint = true);
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _mostrarHint = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _focado = true);
        _ativarHintTemporario();
      },
      onExit: (_) => setState(() {
        _focado = false;
        _mostrarHint = false;
      }),
      child: Focus(
        onFocusChange: (hasFocus) {
          setState(() => _focado = hasFocus);
          if (hasFocus) {
            _ativarHintTemporario();
          } else {
            setState(() => _mostrarHint = false);
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _focado
                      ? const Color(0xFFF5B82E).withOpacity(0.22)
                      : Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _focado
                        ? const Color(0xFFF5B82E)
                        : Colors.transparent,
                    width: 1.8,
                  ),
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: _focado ? const Color(0xFFF5B82E) : Colors.white,
                ),
              ),
            ),
            if (_mostrarHint)
              Positioned(
                top: 44,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141821).withOpacity(0.96),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFF5B82E).withOpacity(0.6),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TvPosterCard extends StatefulWidget {
  final ObraAgrupada obra;
  final VoidCallback onTap;
  final double width;
  final double height;
  final int? rankNumero;
  final double? progresso;
  final bool selecionadoEdicao;
  final bool modoEdicao;

  const TvPosterCard({
    super.key,
    required this.obra,
    required this.onTap,
    this.width = 148,
    this.height = 216,
    this.rankNumero,
    this.progresso,
    this.selecionadoEdicao = false,
    this.modoEdicao = false,
  });

  @override
  State<TvPosterCard> createState() => _TvPosterCardState();
}

class _TvPosterCardState extends State<TvPosterCard> {
  bool _focado = false;

  @override
  Widget build(BuildContext context) {
    final o = widget.obra;
    final img = o.capaUrl.isNotEmpty ? o.capaUrl : o.bannerUrl;

    return Focus(
      onFocusChange: (v) => setState(() => _focado = v),
      child: MouseRegion(
        onEnter: (_) => setState(() => _focado = true),
        onExit: (_) => setState(() => _focado = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _focado ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: SizedBox(
              width: widget.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: widget.height,
                    width: widget.width,
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A23),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.selecionadoEdicao
                            ? Colors.redAccent
                            : (_focado
                                ? const Color(0xFFF5B82E)
                                : Colors.white10),
                        width: (_focado || widget.selecionadoEdicao) ? 2.4 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (img.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Center(
                              child: Icon(Icons.movie_outlined,
                                  color: Colors.white30, size: 36),
                            ),
                          )
                        else
                          const Center(
                            child: Icon(Icons.movie_outlined,
                                color: Colors.white30, size: 36),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 54,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                              ),
                            ),
                          ),
                        ),
                        if (widget.rankNumero != null)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: widget.rankNumero! <= 3
                                    ? const Color(0xFFF5B82E)
                                    : Colors.black87,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '#${widget.rankNumero}',
                                style: TextStyle(
                                  color: widget.rankNumero! <= 3
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        if (!o.disponivelParaAssistir)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.82),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Text(
                                'Em breve',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if (widget.modoEdicao)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: CircleAvatar(
                              radius: 13,
                              backgroundColor: widget.selecionadoEdicao
                                  ? Colors.redAccent
                                  : Colors.black87,
                              child: Icon(
                                widget.selecionadoEdicao
                                    ? Icons.check
                                    : Icons.radio_button_unchecked,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 6,
                          child: Row(
                            children: [
                              if (o.notaImdb > 0)
                                Text(
                                  o.notaImdb.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Color(0xFFF5B82E),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              const Spacer(),
                              if (o.badgePoster.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.75),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    o.badgePoster,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (widget.progresso != null && widget.progresso! > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: widget.progresso,
                              minHeight: 3.5,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFF5B82E)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    o.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          _focado ? const Color(0xFFF5B82E) : Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class CinemaFocusBox extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final double scaleOnFocus;
  final bool autofocus;
  final EdgeInsetsGeometry padding;

  const CinemaFocusBox({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 12,
    this.scaleOnFocus = 1.045,
    this.autofocus = false,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<CinemaFocusBox> createState() => _CinemaFocusBoxState();
}

class _CinemaFocusBoxState extends State<CinemaFocusBox> {
  bool _focused = false;
  bool _hovered = false;

  bool get _ativo => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
               event.logicalKey == LogicalKeyboardKey.enter ||
               event.logicalKey == LogicalKeyboardKey.numpadEnter ||
               event.logicalKey == LogicalKeyboardKey.gameButtonA ||
               event.logicalKey == LogicalKeyboardKey.space)) {
            if (widget.onTap != null) {
              widget.onTap!();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _ativo ? widget.scaleOnFocus : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: _ativo ? const Color(0xFFF5B82E) : Colors.transparent,
                  width: _ativo ? 3.0 : 1.0,
                ),
                boxShadow: _ativo
                    ? [
                        BoxShadow(
                          color: const Color(0xFFF5B82E).withOpacity(0.50),
                          blurRadius: 16,
                          spreadRadius: 1.5,
                        ),
                      ]
                    : const [],
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
