import 'package:flutter/material.dart';

class FeatureTourStep {
  const FeatureTourStep({
    required this.id,
    required this.targetKey,
    required this.title,
    required this.description,
    this.preferredPlacement = TourBubblePlacement.auto,
    this.highlightPadding = 10,
    this.highlightRadius = 20,
  });

  final String id;
  final GlobalKey targetKey;
  final String title;
  final String description;
  final TourBubblePlacement preferredPlacement;
  final double highlightPadding;
  final double highlightRadius;
}

enum TourBubblePlacement { auto, above, below }

class FeatureTourOverlay extends StatefulWidget {
  const FeatureTourOverlay({
    super.key,
    required this.step,
    required this.currentIndex,
    required this.totalSteps,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
    required this.onComplete,
    this.isBusy = false,
  });

  final FeatureTourStep step;
  final int currentIndex;
  final int totalSteps;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;
  final bool isBusy;

  @override
  State<FeatureTourOverlay> createState() => _FeatureTourOverlayState();
}

class _FeatureTourOverlayState extends State<FeatureTourOverlay> {
  int _retryCount = 0;

  @override
  Widget build(BuildContext context) {
    final targetRect = _resolveTargetRect(context, widget.step.targetKey);
    if (targetRect == null) {
      _scheduleRetry();
      return const SizedBox.shrink();
    }
    _retryCount = 0;

    final screenSize = MediaQuery.of(context).size;
    final bubbleWidth = (screenSize.width - 40).clamp(260.0, 420.0).toDouble();
    const bubbleHeightEstimate = 180.0;

    final placement = _resolvePlacement(
      widget.step.preferredPlacement,
      targetRect,
      screenSize,
      bubbleHeightEstimate,
    );

    final bubbleTop = _bubbleTop(
      placement: placement,
      targetRect: targetRect,
      screenHeight: screenSize.height,
      bubbleHeightEstimate: bubbleHeightEstimate,
      stepIndex: widget.currentIndex,
    );
    final bubbleBottom = _bubbleBottom(
      placement: placement,
      targetRect: targetRect,
      screenHeight: screenSize.height,
      stepIndex: widget.currentIndex,
    );
    final bubbleLeft = _bubbleLeft(
      targetRect: targetRect,
      screenWidth: screenSize.width,
      bubbleWidth: bubbleWidth,
    );
    final bubbleTopValue = bubbleTop.isNaN ? null : bubbleTop;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _TourMaskPainter(
              targetRect: targetRect,
              highlightPadding: widget.step.highlightPadding,
              highlightRadius: widget.step.highlightRadius,
            ),
          ),
        ),
        Positioned.fromRect(
          rect: targetRect.inflate(widget.step.highlightPadding),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.step.highlightRadius),
                border: Border.all(
                  color: const Color(0xCCFFFFFF),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55FFFFFF),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: bubbleLeft,
          width: bubbleWidth,
          top: bubbleTopValue,
          bottom: bubbleBottom,
          child: _TourBubble(
            title: widget.step.title,
            description: widget.step.description,
            currentIndex: widget.currentIndex,
            totalSteps: widget.totalSteps,
            isBusy: widget.isBusy,
            onPrevious: widget.onPrevious,
            onNext: widget.onNext,
            onSkip: widget.onSkip,
            onComplete: widget.onComplete,
          ),
        ),
      ],
    );
  }

  void _scheduleRetry() {
    if (_retryCount >= 30) {
      return;
    }
    _retryCount += 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  Rect? _resolveTargetRect(BuildContext overlayContext, GlobalKey targetKey) {
    final targetContext = targetKey.currentContext;
    if (targetContext == null) {
      return null;
    }

    final overlayRenderObject = overlayContext.findRenderObject();
    final renderObject = targetContext.findRenderObject();
    if (overlayRenderObject is! RenderBox ||
        renderObject is! RenderBox ||
        !overlayRenderObject.attached ||
        !renderObject.attached) {
      return null;
    }

    final topLeft = renderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayRenderObject,
    );
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      renderObject.size.width,
      renderObject.size.height,
    );
  }

  TourBubblePlacement _resolvePlacement(
    TourBubblePlacement preferred,
    Rect targetRect,
    Size screenSize,
    double bubbleHeightEstimate,
  ) {
    if (preferred == TourBubblePlacement.above ||
        preferred == TourBubblePlacement.below) {
      return preferred;
    }

    final canPlaceBelow =
        targetRect.bottom + 12 + bubbleHeightEstimate <= screenSize.height - 16;

    return canPlaceBelow ? TourBubblePlacement.below : TourBubblePlacement.above;
  }

  double _bubbleTop({
    required TourBubblePlacement placement,
    required Rect targetRect,
    required double screenHeight,
    required double bubbleHeightEstimate,
    required int stepIndex,
  }) {
    final extraGapForLateSteps = stepIndex >= 2 ? 11.0 : 0.0;
    if (placement == TourBubblePlacement.above) {
      return double.nan;
    }

    return (targetRect.bottom + 2 + extraGapForLateSteps)
        .clamp(16.0, screenHeight - bubbleHeightEstimate - 16)
        .toDouble();
  }

  double? _bubbleBottom({
    required TourBubblePlacement placement,
    required Rect targetRect,
    required double screenHeight,
    required int stepIndex,
  }) {
    if (placement != TourBubblePlacement.above) {
      return null;
    }
    final extraGapForLateSteps = stepIndex >= 2 ? 11.0 : 0.0;
    final gap = 17.0 + extraGapForLateSteps;
    final bottom = (screenHeight - targetRect.top) + gap;
    return bottom.clamp(16.0, screenHeight - 24.0).toDouble();
  }

  double _bubbleLeft({
    required Rect targetRect,
    required double screenWidth,
    required double bubbleWidth,
  }) {
    final centeredToTarget = targetRect.center.dx - (bubbleWidth / 2);
    return centeredToTarget.clamp(20.0, screenWidth - bubbleWidth - 20).toDouble();
  }
}

class _TourBubble extends StatelessWidget {
  const _TourBubble({
    required this.title,
    required this.description,
    required this.currentIndex,
    required this.totalSteps,
    required this.isBusy,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
    required this.onComplete,
  });

  final String title;
  final String description;
  final int currentIndex;
  final int totalSteps;
  final bool isBusy;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
          child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A0F172A),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Step ${currentIndex + 1} / $totalSteps',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: isBusy ? null : onPrevious,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(112, 44),
                    side: const BorderSide(color: Color(0xFFFAC638), width: 1.4),
                    foregroundColor: const Color(0xFFF59E0B),
                    backgroundColor: const Color(0xFFFFFBEB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('Previous'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: isBusy ? null : onNext,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(88, 44),
                    side: const BorderSide(color: Color(0xFFFAC638), width: 1.4),
                    foregroundColor: const Color(0xFF7C2D12),
                    backgroundColor: const Color(0xFFFDE047),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TourMaskPainter extends CustomPainter {
  const _TourMaskPainter({
    required this.targetRect,
    required this.highlightPadding,
    required this.highlightRadius,
  });

  final Rect targetRect;
  final double highlightPadding;
  final double highlightRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          targetRect.inflate(highlightPadding),
          Radius.circular(highlightRadius),
        ),
      );

    canvas.drawPath(
      overlayPath,
      Paint()..color = const Color(0x99000000),
    );
  }

  @override
  bool shouldRepaint(covariant _TourMaskPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.highlightPadding != highlightPadding ||
        oldDelegate.highlightRadius != highlightRadius;
  }
}
    final bubbleTopValue = bubbleTop.isNaN ? null : bubbleTop;
