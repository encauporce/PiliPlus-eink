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
      // 以拇指图标左边那块实心"袖口"为基准：16 号图标里袖口实心块高约 8.5dp，
      // 13 号数字的字面高约 9.2dp，正好上下各比袖口多出一点。
      fontSize: 13,
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
                // 按整体居中数字就会浮上去。实机量得袖口中心比数字中心低约 1.7dp，
                // 把数字下移同样的量，字面上下沿就落在袖口上下沿各自外侧一点。
                Transform.translate(
                  offset: const Offset(0, 2.7),
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
