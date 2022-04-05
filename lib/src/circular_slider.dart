library circular_slider;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sleek_circular_slider/src/slider_animations.dart';
import 'utils.dart';
import 'appearance.dart';
import 'slider_label.dart';
import 'dart:math' as math;

part 'curve_painter.dart';
part 'custom_gesture_recognizer.dart';

typedef void OnChange(double value);
typedef Widget InnerWidget(double percentage);

class CustomSleekCircularSlider extends StatefulWidget {
  final double width;
  final double height;
  final double startValue;
  final double endValue;
  final double min;
  final double max;
  final CircularSliderAppearance appearance;
  final OnChange? onChange;
  final OnChange? onChangeStart;
  final OnChange? onChangeEnd;
  final InnerWidget? innerWidget;
  final Widget? startWidget;
  final Widget? endWidget;
  static const defaultAppearance = CircularSliderAppearance();

  double get angle {
    return valueToAngle(endValue - startValue, min, max, appearance.angleRange);
  }

  double get startAngle {
    return valueToAngle(startValue, min, max, appearance.angleRange);
  }

  Offset get startOffset {
    double radius = math.min(width / 2, height / 2) - appearance.progressBarWidth * 0.5;
    Offset center = Offset(width / 2, height / 2);
    return degreesToCoordinates(center, -math.pi / 2 + startAngle, radius);
  }

  Offset get endOffset {
    double radius = math.min(width / 2, height / 2) - appearance.progressBarWidth * 0.5;
    Offset center = Offset(width / 2, height / 2);
    return degreesToCoordinates(center, -math.pi / 2 + angle, radius);
  }

  const CustomSleekCircularSlider({
    Key? key,
    this.width = 220,
    this.height = 220,
    this.startValue = 0,
    this.endValue = 50,
    this.min = 0,
    this.max = 100,
    this.appearance = defaultAppearance,
    this.onChange,
    this.onChangeStart,
    this.onChangeEnd,
    this.innerWidget,
    this.startWidget,
    this.endWidget,
  })  : assert(min <= max),
        assert(startValue <= endValue),
        assert(startValue >= min && startValue <= max),
        assert(endValue >= min && endValue <= max),
        super(key: key);
  @override
  _CustomSleekCircularSliderState createState() => _CustomSleekCircularSliderState();
}

class _CustomSleekCircularSliderState extends State<CustomSleekCircularSlider> with SingleTickerProviderStateMixin {
  bool _isHandlerSelected = false;
  bool _animationInProgress = false;
  _CurvePainter? _painter;
  double? _oldWidgetAngle;
  double? _oldWidgetValue;
  double? _currentAngle;
  late double _startAngle;
  late double _angleRange;
  double? _selectedAngle;
  double? _rotation;
  SpinAnimationManager? _spinManager;
  ValueChangedAnimationManager? _animationManager;
  late int _appearanceHashCode;

  bool get _interactionEnabled =>
      (widget.onChangeEnd != null || widget.onChange != null && !widget.appearance.spinnerMode);

  @override
  void initState() {
    super.initState();
    _startAngle = widget.appearance.startAngle;
    _angleRange = widget.appearance.angleRange;
    _appearanceHashCode = widget.appearance.hashCode;

    if (!widget.appearance.animationEnabled) {
      return;
    }

    _animate();
  }

  @override
  void didUpdateWidget(CustomSleekCircularSlider oldWidget) {
    if (oldWidget.angle != widget.angle && _currentAngle?.toStringAsFixed(4) != widget.angle.toStringAsFixed(4)) {
      _animate();
    }
    super.didUpdateWidget(oldWidget);
  }

  void _animate() {
    if (!widget.appearance.animationEnabled) {
      _setupPainter();
      _updateOnChange();
      return;
    }
    if (_animationManager == null) {
      _animationManager = ValueChangedAnimationManager(
        tickerProvider: this,
        minValue: widget.min,
        maxValue: widget.max,
        durationMultiplier: widget.appearance.animDurationMultiplier,
      );
    }

    _animationManager!.animate(
        initialValue: widget.endValue - widget.startValue,
        angle: widget.angle,
        oldAngle: _oldWidgetAngle,
        oldValue: _oldWidgetValue,
        valueChangedAnimation: ((double anim, bool animationCompleted) {
          _animationInProgress = !animationCompleted;
          setState(() {
            if (!animationCompleted) {
              _currentAngle = anim;
              // update painter and the on change closure
              _setupPainter();
              _updateOnChange();
            }
          });
        }));
  }

  @override
  Widget build(BuildContext context) {
    /// _setupPainter excution when _painter is null or appearance has changed.
    if (_painter == null || _appearanceHashCode != widget.appearance.hashCode) {
      _appearanceHashCode = widget.appearance.hashCode;
      _setupPainter();
    }
    return RawGestureDetector(gestures: <Type, GestureRecognizerFactory>{
      _CustomPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<_CustomPanGestureRecognizer>(
        () => _CustomPanGestureRecognizer(
          onPanDown: _onPanDown,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
        ),
        (_CustomPanGestureRecognizer instance) {},
      ),
    }, child: _buildRotatingPainter(rotation: _rotation, size: Size(widget.appearance.size, widget.appearance.size)));
  }

  @override
  void dispose() {
    _spinManager?.dispose();
    _animationManager?.dispose();
    super.dispose();
  }

  void _setupPainter({bool counterClockwise = false}) {
    var defaultAngle = _currentAngle ?? widget.angle;
    if (_oldWidgetAngle != null) {
      if (_oldWidgetAngle != widget.angle) {
        _selectedAngle = null;
        defaultAngle = widget.angle;
      }
    }

    _currentAngle = calculateAngle(
        startAngle: _startAngle,
        angleRange: _angleRange,
        selectedAngle: _selectedAngle,
        defaultAngle: defaultAngle,
        counterClockwise: counterClockwise);

    _painter = _CurvePainter(
        startAngle: _startAngle,
        angleRange: _angleRange,
        angle: _currentAngle! < 0.5 ? 0.5 : _currentAngle!,
        appearance: widget.appearance);
    _oldWidgetAngle = widget.angle;
    // _oldWidgetValue = widget.initialValue;
  }

  void _updateOnChange() {
    if (widget.onChange != null && !_animationInProgress) {
      final value = angleToValue(_currentAngle!, widget.min, widget.max, _angleRange);
      widget.onChange!(value);
    }
  }

  Widget _buildRotatingPainter({double? rotation, required Size size}) {
    if (rotation != null) {
      return Transform(
          transform: Matrix4.identity()..rotateZ((rotation) * 5 * math.pi / 6),
          alignment: FractionalOffset.center,
          child: _buildPainter(size: size));
    } else {
      return _buildPainter(size: size);
    }
  }

  Widget _buildPainter({required Size size}) {
    return CustomPaint(
      painter: _painter,
      child: Container(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            _buildChildWidget(),
            Positioned(
              top: widget.startOffset.dy,
              left: widget.startOffset.dx,
              child: widget.startWidget ?? SizedBox.shrink(),
            ),
            Positioned(
              top: widget.endOffset.dy,
              left: widget.endOffset.dx,
              child: widget.endWidget ?? SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildWidget() {
    final value = angleToValue(_currentAngle!, widget.min, widget.max, _angleRange);
    final childWidget = widget.innerWidget != null
        ? widget.innerWidget!(value)
        : SliderLabel(
            value: value,
            appearance: widget.appearance,
          );
    return childWidget;
  }

  void _onPanUpdate(Offset details) {
    if (!_isHandlerSelected) {
      return;
    }
    if (_painter?.center == null) {
      return;
    }
    _handlePan(details, false);
  }

  void _onPanEnd(Offset details) {
    _handlePan(details, true);
    if (widget.onChangeEnd != null) {
      widget.onChangeEnd!(angleToValue(_currentAngle!, widget.min, widget.max, _angleRange));
    }

    _isHandlerSelected = false;
  }

  void _handlePan(Offset details, bool isPanEnd) {
    if (_painter?.center == null) {
      return;
    }
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var position = renderBox.globalToLocal(details);
    final double touchWidth = widget.appearance.progressBarWidth >= 25.0 ? widget.appearance.progressBarWidth : 25.0;
    if (isPointAlongCircle(position, _painter!.center!, _painter!.radius, touchWidth)) {
      _selectedAngle = coordinatesToRadians(_painter!.center!, position);
      // setup painter with new angle values and update onChange
      _setupPainter(counterClockwise: widget.appearance.counterClockwise);
      _updateOnChange();
      setState(() {});
    }
  }

  bool _onPanDown(Offset details) {
    if (_painter == null || _interactionEnabled == false) {
      return false;
    }
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var position = renderBox.globalToLocal(details);

    final angleWithinRange = isAngleWithinRange(
        startAngle: _startAngle,
        angleRange: _angleRange,
        touchAngle: coordinatesToRadians(_painter!.center!, position),
        previousAngle: _currentAngle,
        counterClockwise: widget.appearance.counterClockwise);
    if (!angleWithinRange) {
      return false;
    }

    final double touchWidth = widget.appearance.progressBarWidth >= 25.0 ? widget.appearance.progressBarWidth : 25.0;

    if (isPointAlongCircle(position, _painter!.center!, _painter!.radius, touchWidth)) {
      _isHandlerSelected = true;
      if (widget.onChangeStart != null) {
        widget.onChangeStart!(angleToValue(_currentAngle!, widget.min, widget.max, _angleRange));
      }
      _onPanUpdate(details);
    } else {
      _isHandlerSelected = false;
    }

    return _isHandlerSelected;
  }
}
