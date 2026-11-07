import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pbenum.dart'
    show PlaylistSource;
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/audio/view.dart';
import 'package:PiliPlus/pages/dynamics/widgets/forward_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/live_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/live_panel_sub.dart';
import 'package:PiliPlus/pages/dynamics/widgets/live_rcmd_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/video_panel.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';

Widget noneWidget(ThemeData theme, String? tips) => Row(
  spacing: 5,
  children: [
    Icon(
      Icons.error,
      size: 18,
      color: theme.colorScheme.outline,
    ),
    Text(
      tips ?? '已失效',
      style: TextStyle(color: theme.colorScheme.outline),
    ),
  ],
);

Widget module(
  BuildContext context, {
  required int floor,
  required ThemeData theme,
  required DynamicItemModel item,
  required bool isSave,
  required bool isDetail,
}) {
  final child = _moduleBody(
    context,
    floor: floor,
    theme: theme,
    item: item,
    isSave: isSave,
    isDetail: isDetail,
  );
  // 顶层卡片的左右 12dp 留白在这里统一收口。
  // 以前只有视频卡、直播卡、合集卡各自补 12，活动卡、音乐卡、订阅卡的 Material
  // 黑框直接贴到内容区两端：左边框正好压在左侧 UP 栏那条 1dp 分界线上，
  // 1dp + 1dp 叠成 2dp 的黑竖线，右边框则贴屏。改成统一包一层后，
  // 所有卡片边框与正文、操作栏对齐，内嵌层不再额外缩进（由父级 padding 负责）。
  // 转发引用块自己在 floor == 2 时已有 margin，避免重复缩进。
  return floor == 1 && item.type != 'DYNAMIC_TYPE_FORWARD'
      ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: child,
        )
      : child;
}

Widget _moduleBody(
  BuildContext context, {
  required int floor,
  required ThemeData theme,
  required DynamicItemModel item,
  required bool isSave,
  required bool isDetail,
}) {
  final moduleDynamic = item.modules.moduleDynamic;
  final major = moduleDynamic?.major;

  if (major?.type == 'MAJOR_TYPE_NONE') {
    return noneWidget(theme, major?.none?.tips);
  }

  switch (item.type) {
    case 'DYNAMIC_TYPE_NONE':
      return Row(
        spacing: 4,
        children: [
          const Icon(FontAwesomeIcons.ghost, size: 14),
          Text(major!.none!.tips!),
        ],
      );
    // 图文
    case 'DYNAMIC_TYPE_DRAW':
    // 文章
    case 'DYNAMIC_TYPE_ARTICLE':
    case 'DYNAMIC_TYPE_WORD':
      return const SizedBox.shrink();
    // 视频
    case 'DYNAMIC_TYPE_AV':
    case 'DYNAMIC_TYPE_UGC_SEASON':
    case 'DYNAMIC_TYPE_PGC':
    case 'DYNAMIC_TYPE_PGC_UNION':
    case 'DYNAMIC_TYPE_COURSES_SEASON':
      return videoSeasonWidget(
        context,
        theme: theme,
        item: item,
        floor: floor,
        isSave: isSave,
        isDetail: isDetail,
      );
    // 转发
    case 'DYNAMIC_TYPE_FORWARD':
      return forwardPanel(
        context,
        theme: theme,
        isSave: isSave,
        orig: item.orig!,
        isDetail: isDetail,
        floor: floor + 1,
      );
    // 直播
    case 'DYNAMIC_TYPE_LIVE_RCMD':
      return liveRcmdPanel(
        context,
        theme: theme,
        isDetail: isDetail,
        item: item,
        floor: floor,
      );
    // 直播
    case 'DYNAMIC_TYPE_LIVE':
      return livePanel(
        context,
        theme: theme,
        item: item,
        floor: floor,
        isDetail: isDetail,
      );
    // 活动
    case 'DYNAMIC_TYPE_COMMON_SQUARE':
      final common = major?.common ?? major?.upowerCommon;
      if (common == null) return const SizedBox.shrink();
      return Material(
        // 墨水屏：8% 灰底在黑白屏上是脏灰，统一改白底 + 1dp 黑框
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Style.mdRadius,
          side: BorderSide(color: theme.colorScheme.outline, width: 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: Style.mdRadius,
          onTap: () {
            try {
              String url = common.jumpUrl!;
              if (url.contains('bangumi/play') &&
                  PageUtils.viewPgcFromUri(url)) {
                return;
              }
              PageUtils.handleWebview(url, inApp: true);
            } catch (_) {}
          },
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              top: 10,
              right: 12,
              bottom: 10,
            ),
            child: Row(
              spacing: 10,
              children: [
                if (common.cover?.isNotEmpty ?? false)
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                    child: CachedNetworkImage(
                      width: 45,
                      height: 45,
                      fit: BoxFit.cover,
                      memCacheWidth: 45.cacheSize(context),
                      imageUrl: ImageUtils.safeThumbnailUrl(common.cover),
                    ),
                  ),
                Expanded(
                  child: Column(
                    spacing: 2,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${common.titlePrefix ?? ''}${common.title ?? ''}',
                        style: TextStyle(color: theme.colorScheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (common.desc?.isNotEmpty ?? false)
                        Text(
                          common.desc!,
                          style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontSize: theme.textTheme.labelMedium!.fontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    case 'DYNAMIC_TYPE_MUSIC':
      final music = major!.music!;
      return Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Style.mdRadius,
          side: BorderSide(color: theme.colorScheme.outline, width: 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: Style.mdRadius,
          onTap: () => AudioPage.toAudioPage(
            oid: music.id!,
            itemType: 3,
            from: PlaylistSource.AUDIO_CARD,
          ),
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              top: 10,
              right: 12,
              bottom: 10,
            ),
            child: Row(
              spacing: 10,
              children: [
                NetworkImgLayer(
                  width: 45,
                  height: 45,
                  src: music.cover,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(8),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        music.title!,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        music.label!,
                        style: TextStyle(
                          color: theme.colorScheme.outline,
                          fontSize: theme.textTheme.labelMedium!.fontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    case 'DYNAMIC_TYPE_MEDIALIST':
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (major?.medialist?.cover?.isNotEmpty == true) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                Hero(
                  tag: major!.medialist!.cover!,
                  child: NetworkImgLayer(
                    width: 180,
                    height: 110,
                    src: major.medialist!.cover,
                  ),
                ),
                PBadge(
                  right: 6,
                  top: 6,
                  text: major.medialist!.badge?.text,
                ),
              ],
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: SizedBox(
              height: 110,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    major!.medialist!.title!,
                    style: TextStyle(
                      fontSize: theme.textTheme.titleMedium!.fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (major.medialist?.subTitle != null) ...[
                    const Spacer(),
                    Text(
                      major.medialist!.subTitle!,
                      style: TextStyle(
                        fontSize: theme.textTheme.labelLarge!.fontSize,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );

    case 'DYNAMIC_TYPE_SUBSCRIPTION_NEW'
        when major?.type == 'MAJOR_TYPE_SUBSCRIPTION_NEW':
      return livePanelSub(
        context,
        theme: theme,
        isDetail: isDetail,
        item: item,
        floor: floor,
      );

    default:
      return Text('暂未支持的类型: \n${item.idStr}\n${item.type}');
  }
}
