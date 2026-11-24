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
    this.height = 40,
    this.width = 152,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1D2230),
            Color(0xFF0D1017),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFF5B82E).withOpacity(0.55),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF5B82E).withOpacity(0.16),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: height * 0.64,
            height: height * 0.64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFDF73), Color(0xFFF5B82E), Color(0xFFC98A12)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF5B82E).withOpacity(0.45),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              color: const Color(0xFF0B0D12),
              size: height * 0.48,
            ),
          ),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Cine',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: height * 0.48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                TextSpan(
                  text: 'MAX',
                  style: TextStyle(
                    color: const Color(0xFFF5B82E),
                    fontSize: height * 0.48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
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
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _focado = false;
  Timer? _timer;

  void _removerOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _mostrarOverlay() {
    _removerOverlay();
    _timer?.cancel();
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 190,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 6),
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141821).withOpacity(0.98),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFF5B82E).withOpacity(0.85)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) _removerOverlay();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _removerOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: CinemaFocusBox(
        onTap: widget.onPressed,
        borderRadius: 24,
        scaleOnFocus: 1.12,
        onFocusChanged: (hasFocus) {
          if (mounted) setState(() => _focado = hasFocus);
          if (hasFocus) {
            _mostrarOverlay();
          } else {
            _removerOverlay();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: _focado
                ? const Color(0xFFF5B82E).withOpacity(0.24)
                : Colors.white.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: _focado ? const Color(0xFFF5B82E) : Colors.white,
          ),
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
  final VoidCallback? onFocused;

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
    this.onFocused,
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

    return CinemaFocusBox(
      onTap: widget.onTap,
      borderRadius: 10,
      scaleOnFocus: 1.05,
      onFocusChanged: (v) {
        if (mounted) setState(() => _focado = v);
        if (v) widget.onFocused?.call();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final usarFlex = constraints.hasBoundedHeight && constraints.maxHeight < (widget.height + 28);
          final cardW = constraints.hasBoundedWidth && constraints.maxWidth < widget.width ? constraints.maxWidth : widget.width;
          final posterH = usarFlex ? (constraints.maxHeight - 24).clamp(110.0, widget.height) : widget.height;
          return SizedBox(
            width: cardW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: posterH,
                  width: cardW,
              decoration: BoxDecoration(
                color: const Color(0xFF161A23),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.selecionadoEdicao
                      ? Colors.redAccent
                      : (_focado ? const Color(0xFFF5B82E) : Colors.white10),
                  width: (_focado || widget.selecionadoEdicao) ? 2.2 : 1,
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
                      memCacheWidth: 220,
                      fadeInDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.movie_outlined, color: Colors.white30, size: 36),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(Icons.movie_outlined, color: Colors.white30, size: 36),
                    ),
                  if (widget.modoEdicao)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: widget.selecionadoEdicao ? Colors.redAccent : Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.selecionadoEdicao ? Icons.check : Icons.circle_outlined,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  if (widget.rankNumero != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.rankNumero! <= 3
                              ? const Color(0xFFF5B82E)
                              : Colors.black.withOpacity(0.78),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '#${widget.rankNumero}',
                          style: TextStyle(
                            color: widget.rankNumero! <= 3 ? Colors.black : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (o.notaImdb > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              o.notaImdb.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Color(0xFFF5B82E),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        if (o.badgePoster.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF5B82E)),
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
                color: _focado ? const Color(0xFFF5B82E) : Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
      }),
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
  final ValueChanged<bool>? onFocusChanged;
  final FocusNode? focusNode;

  const CinemaFocusBox({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 12,
    this.scaleOnFocus = 1.045,
    this.autofocus = false,
    this.padding = EdgeInsets.zero,
    this.onFocusChanged,
    this.focusNode,
  });

  @override
  State<CinemaFocusBox> createState() => _CinemaFocusBoxState();
}

class _CinemaFocusBoxState extends State<CinemaFocusBox> {
  bool _focused = false;
  bool _hovered = false;
  DateTime _ultimoAcionamento = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _ativo => _focused || _hovered;

  void _acionar() {
    if (widget.onTap == null) return;
    final agora = DateTime.now();
    if (agora.difference(_ultimoAcionamento).inMilliseconds < 280) return;
    _ultimoAcionamento = agora;
    widget.onTap!();
  }

  bool _isConfirmKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.accept ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.space;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) { if (mounted) setState(() => _hovered = true); },
      onExit: (_) { if (mounted) setState(() => _hovered = false); },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _acionar();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              _acionar();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onFocusChange: (f) {
            if (mounted) setState(() => _focused = f);
            widget.onFocusChanged?.call(f);
          },
          onKeyEvent: (node, event) {
            if (_isConfirmKey(event.logicalKey)) {
              if (event is KeyDownEvent) {
                _acionar();
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: _acionar,
            child: AnimatedScale(
              scale: _ativo ? widget.scaleOnFocus : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: _ativo ? const Color(0xFFF5B82E) : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
