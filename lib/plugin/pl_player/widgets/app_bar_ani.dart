import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:material_ui/material_ui.dart';

class AppBarAni extends StatelessWidget {
  const AppBarAni({
    super.key,
    required this.child,
    required this.controller,
    required this.isTop,
    required this.isFullScreen,
    required this.removeSafeArea,
  });

  final Widget child;
  final AnimationController controller;
  final bool isTop;
  final bool isFullScreen;
  final bool removeSafeArea;

  static final _topPos = Tween<Offset>(
    begin: const Offset(0.0, -1.0),
    end: Offset.zero,
  );

  // 墨水屏：控制条原为黑底 + 白图标，和页面的黑白版式冲突；
  // 改白底 + 黑描边 + 黑图标，暂停时上下两条控制条都嵌在白纸里。
  static const _topDecoration = BoxDecoration(
    color: Colors.white,
    border: Border(
      bottom: BorderSide(color: Colors.black, width: 1.0),
    ),
  );

  static final _bottomPos = Tween<Offset>(
    begin: const Offset(0, 1.2),
    end: Offset.zero,
  );

  static const _bottomDecoration = BoxDecoration(
    color: Colors.white,
    border: Border(
      top: BorderSide(color: Colors.black, width: 1.0),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: controller.drive(isTop ? _topPos : _bottomPos),
      child: DecoratedBox(
        decoration: isTop ? _topDecoration : _bottomDecoration,
        child: removeSafeArea
            ? child
            : ViewSafeArea(
                left: isFullScreen,
                right: isFullScreen,
                child: child,
              ),
      ),
    );
  }
}
