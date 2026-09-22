// lib/widgets/signature_pad.dart
//
// Minimal draw-your-signature widget, built with CustomPainter rather than
// a new package dependency. Exposes a GlobalKey<SignaturePadState> so the
// parent can call `capture()` to get PNG bytes, and `clear()`/`isEmpty`.
// [onChanged] fires when a stroke ends or the pad is cleared, so the parent
// can re-evaluate whether the form is complete.

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme/app_theme.dart';
import 'dashed_border.dart';

class SignaturePad extends StatefulWidget {
  final double height;
  final VoidCallback? onChanged;
  const SignaturePad({super.key, this.height = 130, this.onChanged});

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final GlobalKey _repaintKey = GlobalKey();
  final List<List<Offset>> _strokes = [];

  bool get isEmpty => _strokes.isEmpty;

  void clear() {
    setState(() => _strokes.clear());
    widget.onChanged?.call();
  }

  Future<Uint8List?> capture() async {
    if (_strokes.isEmpty) return null;
    final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The dashed border sits OUTSIDE the RepaintBoundary so it is not
        // included in the captured signature image.
        CustomPaint(
          foregroundPainter: const DashedBorderPainter(color: AppColors.dustyRose, radius: 12),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RepaintBoundary(
                key: _repaintKey,
                child: Container(
                  color: Colors.white,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) => setState(() => _strokes.add([details.localPosition])),
                    onPanUpdate: (details) => setState(() => _strokes.last.add(details.localPosition)),
                    onPanEnd: (_) => widget.onChanged?.call(),
                    child: CustomPaint(
                      painter: _SignaturePainter(_strokes),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _strokes.isEmpty ? null : clear,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Clear Signature', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}