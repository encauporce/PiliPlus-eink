import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dyn_content.dart';
import 'package:PiliPlus/pages/dynamics/widgets/module_panel.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

Widget forwardPanel(
  BuildContext context, {
  required int floor,
  required ThemeData theme,
  required DynamicItemModel orig,
  required bool isSave,
  required bool isDetail,
}) {
  final moduleDynamic = orig.modules.moduleDynamic;
  final major = moduleDynamic?.major;
  final isNoneMajor = major?.type == 'MAJOR_TYPE_NONE';

  Widget child;

  if (isNoneMajor) {
    child = noneWidget(theme, major?.none?.tips);
  } else {
    child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _forwardAuthor(
          theme: theme,
          moduleAuthor: orig.modules.moduleAuthor!,
          isSave: isSave,
        ),
        const SizedBox(height: 5),
        ...dynContent(
          context,
          theme: theme,
          isSave: isSave,
          isDetail: isDetail,
          item: orig,
          floor: floor + 1,
        ),
      ],
    );
  }

  child = Container(
    // 引用块原来左右没有留白，横向一直顶到内容区两端：左边框正好压在
    // 左侧 UP 栏那条 1dp 分界线上，1dp + 1dp 叠成一条 2dp 的黑竖线；
    // 右边框则贴在屏幕边缘。这里补上和正文、视频卡一致的 12dp 留白。
    // 注意 module() 调用时传的是 floor + 1，所以卡片里的第一层引用块是 2；
    // 引用块里再嵌套的转发（3 层）本身已经在外层 15dp 内边距中，不再加。
    margin: floor == 2 ? const EdgeInsets.symmetric(horizontal: 12) : null,
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
    // 墨水屏：原来用 8% 灰底当"引用块"，黑白屏上是一块脏灰，
    // 改成白底 + 1dp 黑框 + 8dp 圆角。
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      border: Border.all(color: theme.colorScheme.outline, width: 1.0),
    ),
    child: child,
  );

  if (isNoneMajor) {
    return child;
  }

  void showMore() {
    String? title, cover, bvid;
    switch (orig.type) {
      case 'DYNAMIC_TYPE_AV':
        title = major?.archive?.title;
        cover = major?.archive?.cover;
        bvid = major?.archive?.bvid;
        break;
      case 'DYNAMIC_TYPE_UGC_SEASON':
        title = major?.ugcSeason?.title;
        cover = major?.ugcSeason?.cover;
        bvid = major?.ugcSeason?.bvid;
        break;
      case 'DYNAMIC_TYPE_PGC' || 'DYNAMIC_TYPE_PGC_UNION':
        title = major?.pgc?.title;
        cover = major?.pgc?.cover;
        break;
      case 'DYNAMIC_TYPE_LIVE_RCMD':
        title = major?.liveRcmd?.title;
        cover = major?.liveRcmd?.cover;
        break;
      case 'DYNAMIC_TYPE_LIVE':
        title = major?.live?.title;
        cover = major?.live?.cover;
        break;
      default:
        return;
    }
    if (cover != null) {
      imageSaveDialog(
        title: title,
        cover: cover,
        bvid: bvid,
      );
    }
  }

  return InkWell(
    onTap: () => PageUtils.pushDynDetail(orig),
    onLongPress: showMore,
    onSecondaryTap: PlatformUtils.isMobile ? null : showMore,
    child: child,
  );
}

Widget _forwardAuthor({
  required ThemeData theme,
  required ModuleAuthorModel moduleAuthor,
  required bool isSave,
}) {
  final isNormalAuth = moduleAuthor.type == 'AUTHOR_TYPE_NORMAL';
  return Row(
    children: [
      GestureDetector(
        onTap: isNormalAuth
            ? () => Get.toNamed('/member?mid=${moduleAuthor.mid}')
            : null,
        child: Text(
          '${isNormalAuth ? '@' : ''}${moduleAuthor.name}',
          style: TextStyle(color: theme.colorScheme.primary),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        isSave
            ? DateFormatUtils.format(
                moduleAuthor.pubTs,
                format: DateFormatUtils.longFormatDs,
              )
            : DateFormatUtils.dateFormat(moduleAuthor.pubTs),
        style: TextStyle(
          color: theme.colorScheme.outline,
          fontSize: theme.textTheme.labelSmall!.fontSize,
        ),
      ),
    ],
  );
}
