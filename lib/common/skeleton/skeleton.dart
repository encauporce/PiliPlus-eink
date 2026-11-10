import 'package:material_ui/material_ui.dart';

class Skeleton extends StatelessWidget {
  final Widget child;

  const Skeleton({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 墨水屏：去除 60fps 循环扫光动画与重绘，保持静态占位
    return child;
  }
}
