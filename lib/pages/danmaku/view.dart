import 'dart:convert';

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/models/common/video/video_alignment_type.dart';
import 'package:PiliPlus/pages/danmaku/controller.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 传入播放器控制器，监听播放进度，加载对应弹幕
class PlDanmaku extends StatefulWidget {
  final int cid;
  final PlPlayerController playerController;
  final bool isPipMode;
  final bool isFullScreen;
  final bool isFileSource;
  final Size size;

  const PlDanmaku({
    super.key,
    required this.cid,
    required this.playerController,
    this.isPipMode = false,
    required this.isFullScreen,
    required this.isFileSource,
    required this.size,
  });

  @override
  State<PlDanmaku> createState() => _PlDanmakuState();

  bool get notFullscreen => !isFullScreen || isPipMode;
}

class _PlDanmakuState extends State<PlDanmaku> {
  PlPlayerController get playerController => widget.playerController;

  late final PlDanmakuController _plDanmakuController;
  DanmakuController<DanmakuExtra>? _controller;
  int latestAddedPosition = -1;

  // ---- 留言板模式（画面对齐为左/右时启用）----
  // 飞行弹幕在画面只占一侧时会把另一侧黑边浪费掉，而且贴边对齐后弹幕飞出屏幕就看不全。
  // 这里改成直播留言板那种一条一行的紧凑列表，行间画细分割线。
  final List<_BoardDanmaku> _board = [];
  final ScrollController _boardScroll = ScrollController();
  static const int _boardMaxLen = 300;
  bool _boardAttached = false;

  bool get _boardMode =>
      playerController.videoAlignment.value != VideoAlignmentType.center;

  @override
  void initState() {
    super.initState();
    _plDanmakuController = PlDanmakuController(
      widget.cid,
      playerController,
      widget.isFileSource,
    );
    if (playerController.enableShowDanmaku.value) {
      if (widget.isFileSource) {
        _plDanmakuController.initFileDmIfNeeded();
      } else {
        _plDanmakuController.queryDanmaku(
          DmUtils.calcSegment(playerController.positionInMilliseconds),
        );
      }
    }
    playerController
      ..addStatusLister(playerListener)
      ..addPositionListener(videoPositionListen);
  }

  @override
  void didUpdateWidget(PlDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notFullscreen != widget.notFullscreen &&
        !DanmakuOptions.sameFontScale) {
      _controller?.updateOption(
        DanmakuOptions.get(
          notFullscreen: widget.notFullscreen,
          speed: playerController.playbackSpeed,
        ),
      );
    }
  }

  // 播放器状态监听
  void playerListener(PlayerStatus status) {
    if (_controller case final controller?) {
      if (status.isPlaying) {
        controller.resume();
      } else {
        controller.pause();
      }
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  void videoPositionListen(Duration position) {
    // 留言板模式下没有 DanmakuScreen（_controller 为 null），所以不能在这里
    // 提前用 _controller == null 拦掉，否则列表收不到任何弹幕。
    if (!playerController.enableShowDanmaku.value) {
      return;
    }

    if (!playerController.showDanmaku && !widget.isPipMode) {
      return;
    }

    if (!playerController.playerStatus.isPlaying) {
      return;
    }

    int currentPosition = position.inMilliseconds;
    currentPosition -= currentPosition % 100; //取整百的毫秒数
    if (currentPosition == latestAddedPosition) {
      return;
    }
    latestAddedPosition = currentPosition;

    List<DanmakuElem>? currentDanmakuList = _plDanmakuController
        .getCurrentDanmaku(currentPosition);
    if (currentDanmakuList != null) {
      if (_boardMode) {
        _appendToBoard(currentDanmakuList);
        return;
      }
      if (_controller == null) {
        return;
      }
      final blockColorful = DanmakuOptions.blockColorful;
      final danmakuWeight = DanmakuOptions.danmakuWeight;
      for (DanmakuElem e in currentDanmakuList) {
        if (e.weight < danmakuWeight) continue;
        if (e.mode == 7) {
          try {
            _controller!.addDanmaku(
              SpecialDanmakuContentItem.fromList(
                DmUtils.decimalToColor(e.color),
                e.fontsize.toDouble(),
                jsonDecode(e.content.replaceAll('\n', '\\n')),
                extra: VideoDanmaku(
                  id: e.id.toInt(),
                  mid: e.midHash,
                  like: e.likeCount.toInt(),
                ),
              ),
            );
          } catch (_) {}
        } else {
          _controller!.addDanmaku(
            DanmakuContentItem(
              e.content,
              color: blockColorful
                  ? Colors.white
                  : DmUtils.decimalToColor(e.color),
              type: DmUtils.getPosition(e.mode),
              isColorful:
                  playerController.showVipDanmaku &&
                  e.colorful == DmColorfulType.VipGradualColor,
              count: e.count > 1 ? e.count : null,
              selfSend: e.isSelf,
              extra: VideoDanmaku(
                id: e.id.toInt(),
                mid: e.midHash,
                like: e.likeCount.toInt(),
              ),
            ),
          );
        }
      }
    }
  }

  /// 把当前时刻的弹幕塞进留言板列表。同一个 100ms 桶只会被取一次，
  /// 所以不需要再去重；只在真的有新条目时重建，避免墨水屏无意义刷新。
  void _appendToBoard(List<DanmakuElem> list) {
    final weight = DanmakuOptions.danmakuWeight;
    var changed = false;
    for (final e in list) {
      if (e.weight < weight) continue;
      final content = e.content.trim();
      if (content.isEmpty) continue;
      _board.add(
        _BoardDanmaku(time: latestAddedPosition, content: content),
      );
      changed = true;
    }
    if (!changed) return;
    if (_board.length > _boardMaxLen) {
      _board.removeRange(0, _board.length - _boardMaxLen);
    }
    if (mounted) setState(() {});
    // 新条目落到列表底部，跟着滚过去
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_boardScroll.hasClients) {
        _boardScroll.jumpTo(_boardScroll.position.maxScrollExtent);
      }
    });
  }

  /// 画面在当前容器里实际占多宽。左右对齐时另一侧空出来的黑边正好放留言板。
  double _videoWidth(Size size) {
    final fit = playerController.videoFit.value;
    var ar = fit.aspectRatio;
    if (ar == null) {
      // PlatformVideoController 没有 value，只能从 texture 的 rect 反推分辨率
      final rect = playerController.videoController?.rect.value;
      final w = rect?.width;
      final h = rect?.height;
      if (w != null && h != null && w > 0 && h > 0) ar = w / h;
    }
    if (ar == null) return size.width;
    switch (fit.boxFit) {
      case BoxFit.fill:
      case BoxFit.cover:
      case BoxFit.fitWidth:
        return size.width;
      default:
        final w = size.height * ar;
        return w > size.width ? size.width : w;
    }
  }

  Widget _buildBoard() {
    final size = widget.size;
    final align = playerController.videoAlignment.value;
    // align == left 表示画面贴左，留言板落到右边，反之亦然
    final boardOnRight = align == VideoAlignmentType.left;
    final blank = (size.width - _videoWidth(size))
        .clamp(0.0, size.width)
        .toDouble();
    // 黑边够宽就整块用上，不够就让列表压住画面一侧，别缩成一条缝
    final boardW = blank >= size.width * 0.3 ? blank : size.width * 0.4;
    final side = const BorderSide(color: Colors.black, width: 1.0);
    return Stack(
      children: [
        Positioned(
          top: 0,
          bottom: 0,
          left: boardOnRight ? null : 0,
          right: boardOnRight ? 0 : null,
          width: boardW,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                left: boardOnRight ? side : BorderSide.none,
                right: boardOnRight ? BorderSide.none : side,
              ),
            ),
            child: ListView.builder(
              controller: _boardScroll,
              padding: EdgeInsets.zero,
              itemCount: _board.length,
              itemBuilder: (_, index) {
                final item = _board[index];
                final m = item.time ~/ 60000;
                final s = (item.time % 60000) ~/ 1000;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Color(0xFFCCCCCC),
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$m:${s.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          color: Color(0xFF666666),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.content,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    playerController
      ..removePositionListener(videoPositionListen)
      ..removeStatusLister(playerListener);
    _plDanmakuController.dispose();
    _boardScroll.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final option = DanmakuOptions.get(
      notFullscreen: widget.notFullscreen,
      speed: playerController.playbackSpeed,
    );
    return Obx(() {
      // 必须在这个闭包里读，才会订阅 videoAlignment 的变化
      final board = _boardMode;
      if (board != _boardAttached) {
        _boardAttached = board;
        if (board) {
          // DanmakuScreen 会被销毁并 dispose 掉 canvas 的 controller，这里必须
          // 把播放器上的引用一起清掉，否则发弹幕等逻辑会拿到已释放的对象。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            playerController.danmakuController = null;
          });
        }
      }
      return AnimatedOpacity(
        opacity: playerController.enableShowDanmaku.value
            ? playerController.danmakuOpacity.value
            : 0,
        duration: const Duration(milliseconds: 100),
        // 画面对齐选了左/右：留着飞行弹幕会从贴边那侧飞出去，改成留言板列表
        child: board
            ? _buildBoard()
            : DanmakuScreen<DanmakuExtra>(
                createdController: (e) {
                  playerController.danmakuController = _controller = e;
                },
                option: option,
                size: widget.size,
              ),
      );
    });
  }
}

class _BoardDanmaku {
  const _BoardDanmaku({required this.time, required this.content});
  final int time;
  final String content;
}
