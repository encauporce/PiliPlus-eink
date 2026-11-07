// 视频or合集
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/svg/play_icon.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:material_ui/material_ui.dart';

Widget videoSeasonWidget(
  BuildContext context, {
  required int floor,
  required ThemeData theme,
  required DynamicItemModel item,
  required bool isSave,
  required bool isDetail,
}) {
  // type archive  ugcSeason
  // archive 视频/显示发布人
  // ugcSeason 合集/不显示发布人

  DynamicArchiveModel? video = switch (item.type) {
    'DYNAMIC_TYPE_AV' => item.modules.moduleDynamic?.major?.archive,
    'DYNAMIC_TYPE_UGC_SEASON' => item.modules.moduleDynamic?.major?.ugcSeason,
    'DYNAMIC_TYPE_PGC' ||
    'DYNAMIC_TYPE_PGC_UNION' => item.modules.moduleDynamic?.major?.pgc,
    'DYNAMIC_TYPE_COURSES_SEASON' => item.modules.moduleDynamic?.major?.courses,
    _ => null,
  };

  if (video == null) {
    return const SizedBox.shrink();
  }

  // 左右 12dp 留白统一由 module_panel 包（见 module()），这里不再各自处理，
  // 否则内嵌层会被叠加缩进。
  return Column(
      spacing: 6,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (video.cover case final cover?)
          Stack(
            clipBehavior: Clip.none,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => NetworkImgLayer(
                  width: constraints.maxWidth,
                  height: constraints.maxWidth / Style.aspectRatio,
                  src: cover,
                  quality: 40,
                ),
              ),
              if (video.badge?.text case final badge?)
                PBadge(
                  text: badge,
                  top: 8.0,
                  right: 10.0,
                  bottom: null,
                  left: null,
                  type: switch (badge) {
                    '充电专属' => PBadgeType.error,
                    _ => PBadgeType.primary,
                  },
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 墨水屏：原来用「黑→透明」渐变托白字，渐变在黑白屏上会抖成一片噪点，
                      // 白字遇到亮封面还会糊掉。改成实心黑胶囊 + 白字，边缘干净。
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              borderRadius: .all(.circular(4)),
                            ),
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: theme.textTheme.labelMedium!.fontSize,
                                color: Colors.white,
                              ),
                              child: Row(
                                mainAxisSize: .min,
                                children: [
                                  if (video.durationText
                                      case final durationText?) ...[
                                    Text(durationText),
                                    const SizedBox(width: 6),
                                  ],
                                  if (video.stat case final stat?) ...[
                                    Text('${NumUtils.numFormat(stat.play)}播放'),
                                    const SizedBox(width: 6),
                                    Text('${NumUtils.numFormat(stat.danmu)}弹幕'),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 白色播放图标压在亮封面上会看不见，垫一块黑底。
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          borderRadius: .all(.circular(6)),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const PlayIcon(size: 30),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (video.title case final title?)
          Text(
            title,
            maxLines: isDetail ? null : 1,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: isDetail ? null : TextOverflow.ellipsis,
          ),
    ],
  );
}
