import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';

class ZanButtonGrpc extends StatelessWidget {
  const ZanButtonGrpc({
    super.key,
    required this.replyItem,
  });

  final ReplyInfo replyItem;

  Future<void> onHateReply(
    BuildContext context, {
    required bool isLike,
    required bool isDislike,
  }) async {
    feedBack();
    final int oid = replyItem.oid.toInt();
    final int rpid = replyItem.id.toInt();
    final int action = isDislike ? 0 : 1;
    final res = await ReplyHttp.hateReply(
      type: replyItem.type.toInt(),
      action: action,
      oid: oid,
      rpid: rpid,
    );
    // SmartDialog.dismiss();
    if (res.isSuccess) {
      SmartDialog.showToast(isDislike ? '取消踩' : '点踩成功');
      if (isDislike) {
        replyItem.replyControl.action = $fixnum.Int64.ZERO;
      } else {
        if (isLike) replyItem.like -= $fixnum.Int64.ONE;
        replyItem.replyControl.action = $fixnum.Int64.TWO;
      }
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    } else {
      res.toast();
    }
  }

  // 评论点赞
  Future<void> onLikeReply(
    BuildContext context, {
    required bool isLike,
    required bool isDislike,
  }) async {
    feedBack();
    final int oid = replyItem.oid.toInt();
    final int rpid = replyItem.id.toInt();
    // 1 已点赞 2 不喜欢 0 未操作
    final int action = isLike ? 0 : 1;
    final res = await ReplyHttp.likeReply(
      type: replyItem.type.toInt(),
      oid: oid,
      rpid: rpid,
      action: action,
    );
    if (res.isSuccess) {
      SmartDialog.showToast(isLike ? '取消赞' : '点赞成功');
      if (isLike) {
        replyItem
          ..like -= $fixnum.Int64.ONE
          ..replyControl.action = $fixnum.Int64.ZERO;
      } else {
        replyItem
          ..like += $fixnum.Int64.ONE
          ..replyControl.action = $fixnum.Int64.ONE;
      }
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    } else {
      res.toast();
    }
  }

  static void _toastNotLogin() {
    SmartDialog.showToast('账号未登录');
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = Accounts.main.isLogin;
    final ThemeData theme = Theme.of(context);
    late bool isProcessing = false;
    final action = replyItem.replyControl.action;
    final isLike = action == $fixnum.Int64.ONE;
    final isDislike = action == $fixnum.Int64.TWO;
    final outline = theme.colorScheme.outline;
    final primary = theme.colorScheme.primary;
    // 踩、赞、赞数三项要看起来像一组。原来两个按钮一个吃 styleFrom 的
    // minimumSize(40)，一个吃内联 ButtonStyle，内容宽度与内边距不一致，
    // 所以三项在水平方向上被拉开得乱。
    // 统一：零最小尺寸 + 零内边距 + 固定 32 高热区，间距由外层 spacing 控制。
    const buttonStyle = ButtonStyle(
      visualDensity: .compact,
      tapTargetSize: .shrinkWrap,
      padding: WidgetStatePropertyAll(.zero),
      minimumSize: WidgetStatePropertyAll(Size.zero),
      side: WidgetStatePropertyAll(BorderSide.none),
    );
    final TextStyle numStyle = TextStyle(
      color: isLike ? primary : outline,
      // 以拇指图标左边那块实心"袖口"为基准：16 号图标里袖口实心块高约 20 设备 px，
      // 13 号数字刚好 21px（视觉上持平），14 号约 22.6px，上下各比袖口多出一点。
      fontSize: 14,
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
    );

    @pragma('vm:prefer-inline')
    Future<void> wrapProcessing(
      Future<void> Function(
        BuildContext context, {
        required bool isLike,
        required bool isDislike,
      })
      onLikeOrDislike,
    ) async {
      if (isProcessing) return;
      isProcessing = true;
      await onLikeOrDislike(context, isLike: isLike, isDislike: isDislike);
      isProcessing = false;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 10,
      children: [
        SizedBox(
          height: 32,
          child: TextButton(
            style: buttonStyle,
            onPressed: isLogin
                ? () => wrapProcessing(onHateReply)
                : _toastNotLogin,
            // thumbsDown 是 thumbsUp 的上下镜像，字形框一样高，但左侧实心
            // "袖口"被翻到了上半部分：实测踩袖口 y 1032-1052、赞袖口 y 1038-1059，
            // 相差 6.5px（dpr 2.25 → 2.9dp）。这里把踩整体下移，让两块实心
            // 对齐成一条线，拇指各自朝上/朝下，视觉上才是一组。
            child: Transform.translate(
              offset: const Offset(0, 2.9),
              child: Icon(
                isDislike
                    ? FontAwesomeIcons.solidThumbsDown
                    : FontAwesomeIcons.thumbsDown,
                size: 16,
                color: isDislike ? primary : outline,
                semanticLabel: isDislike ? '已踩' : '点踩',
              ),
            ),
          ),
        ),
        SizedBox(
          height: 32,
          child: TextButton(
            style: buttonStyle,
            onPressed: isLogin
                ? () => wrapProcessing(onLikeReply)
                : _toastNotLogin,
            child: Row(
              spacing: 4,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  isLike
                      ? FontAwesomeIcons.solidThumbsUp
                      : FontAwesomeIcons.thumbsUp,
                  size: 16,
                  color: isLike ? primary : outline,
                  semanticLabel: isLike ? '已赞' : '点赞',
                ),
                // 垂直方向认袖口方块而不是整个拇指外形：拇指尖比袖口高出一截，
                // 按整体居中数字就会浮上去。实机量：2.1dp 时数字上沿与袖口齐平、
                // 下沿多 2px（整体偏下 1px），回填一格让上下各多出 1px。
                Transform.translate(
                  offset: const Offset(0, 1.7),
                  child: Text(
                    NumUtils.numFormat(replyItem.like.toInt()),
                    style: numStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
