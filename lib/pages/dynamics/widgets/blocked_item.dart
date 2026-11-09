import 'package:PiliPlus/models/dynamics/result.dart' show ModuleBlocked;
import 'package:PiliPlus/pages/article/widgets/opus_content.dart'
    show moduleBlockedItem;
import 'package:material_ui/material_ui.dart';

Widget blockedItem(
  BuildContext context, {
  required ThemeData theme,
  required ModuleBlocked blocked,
}) {
  return Padding(
    // 13 → 12：和正文/content() 的左右留白同一条轴，避免这一行比其它行突出 1dp
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
    child: moduleBlockedItem(context, theme.colorScheme, blocked),
  );
}
