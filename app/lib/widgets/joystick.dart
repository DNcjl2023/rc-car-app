import 'dart:math';

import 'package:flutter/material.dart';

/// 虚拟摇杆：拖动输出 [-1,1] 归一化偏移，松手自回中。
/// onChanged(Offset)：x=左右，y=上下（屏幕坐标系，上为负）
class Joystick extends StatefulWidget {
  final double size;
  final ValueChanged<Offset>? onChanged;
  final Widget? child;
  final String label;

  const Joystick({super.key, this.size = 170, this.onChanged, this.child, this.label = 'joy'});

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _offset = Offset.zero;
  bool _active = false;

  void _update(Offset local) {
    final r = widget.size / 2;
    var dx = local.dx - r;
    var dy = local.dy - r;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist > r && dist > 0) {
      dx = dx / dist * r;
      dy = dy / dist * r;
    }
    setState(() {
      _offset = Offset(dx, dy);
      _active = true;
    });
    widget.onChanged?.call(Offset(dx / r, dy / r));
  }

  void _reset() {
    setState(() {
      _offset = Offset.zero;
      _active = false;
    });
    widget.onChanged?.call(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // 用指针级监听：无论指针在哪松开都强制回中（避免拖出控件松手卡死）
    return Listener(
      onPointerDown: (d) {
        debugPrint('[joy] down ${d.localPosition}');
        _update(d.localPosition);
      },
      onPointerMove: (d) {
        if (_active) {
          debugPrint('[joy] move ${d.localPosition}');
          _update(d.localPosition);
        }
      },
      onPointerUp: (_) {
        debugPrint('[joy-${widget.label}] UP');
        _reset();
      },
      onPointerCancel: (_) {
        debugPrint('[joy-${widget.label}] CANCEL');
        _reset();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 十字参考线
            Container(width: 1.5, height: size * 0.72, color: Colors.white.withValues(alpha: 0.12)),
            Container(width: size * 0.72, height: 1.5, color: Colors.white.withValues(alpha: 0.12)),
            // 中位圈
            Container(
              width: size * 0.56,
              height: size * 0.56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
            ),
            // 手柄
            AnimatedContainer(
              duration: _active ? Duration.zero : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(_offset.dx, _offset.dy, 0),
              width: size * 0.40,
              height: size * 0.40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.cyan.shade300,
                    _active ? Colors.cyan.shade600 : Colors.blueGrey.shade600,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}