import 'dart:async';
import 'dart:convert';

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/models/common/video/video_alignment_type.dart';
import 'package:PiliPlus/pages/danmaku/controller.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
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
  // 画面缩到一侧后，另一侧的黑边里用直播留言板那种一条一行的方式滚弹幕，
  // 每条按时长自然消失（不留时间轴）。
  final List<_BoardDanmaku> _board = [];
  static const int _boardMaxLen = 60;
  Timer? _boardTimer;
  bool _boardAttached = false;
  String _dbgKey = '';

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
    // 启动时序里控制器偶尔会停在 center（setting 还没被读到），
    // 以持久化的设置为准补一次，否则「默认画面对齐」选了左右也不生效。
    final prefAlign = Pref.videoAlignment;
    if (playerController.videoAlignment.value != prefAlign) {
      playerController.videoAlignment.value = prefAlign;
    }
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

  /// 一条留言在板上留多久：字数越多读得越久（5s 起），同一句被反复刷
  /// 说明是当前这段的梗，再按重复次数往后加，最长 15s。
  Duration _stayOf(String content, int dup) {
    final len = content.runes.length;
    var ms = 4000 + len * 300;
    if (dup > 1) ms += (dup - 1) * 1500;
    return Duration(milliseconds: ms.clamp(5000, 15000).toInt());
  }

  /// 把当前时刻的弹幕塞进留言板。同一个 100ms 桶只会被取一次，
  /// 所以不需要再去重；只在真的有新条目时重建，避免墨水屏无意义刷新。
  void _appendToBoard(List<DanmakuElem> list) {
    final weight = DanmakuOptions.danmakuWeight;
    final now = DateTime.now();
    var changed = false;
    for (final e in list) {
      if (e.weight < weight) continue;
      final content = e.content.trim();
      if (content.isEmpty) continue;
      // 同一句刷屏就并成一条带次数，位置挪到最新，避免整块板被一句话占满
      final idx = _board.lastIndexWhere((x) => x.content == content);
      final dup = idx >= 0 ? _board[idx].dup + 1 : 1;
      if (idx >= 0) _board.removeAt(idx);
      _board.add(
        _BoardDanmaku(
          content: content,
          dup: dup,
          expireAt: now.add(_stayOf(content, dup)),
        ),
      );
      changed = true;
    }
    if (!changed) return;
    if (_board.length > _boardMaxLen) {
      _board.removeRange(0, _board.length - _boardMaxLen);
    }
    if (mounted) setState(() {});
  }

  /// 到点的留言自己退场。暂停时冻结，免得暂停看画面时整块板被清空。
  void _startBoardTimer() {
    _boardTimer ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (!playerController.playerStatus.isPlaying) return;
      final now = DateTime.now();
      final before = _board.length;
      _board.removeWhere((e) => !e.expireAt.isAfter(now));
      if (_board.length != before) setState(() {});
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
    // align == left 表示画面贴左，板落到右边，反之亦然
    final boardOnRight = align == VideoAlignmentType.left;
    final blank = (size.width - _videoWidth(size))
        .clamp(0.0, size.width)
        .toDouble();
    final dbg = '${align.index}|${blank.toStringAsFixed(0)}';
    if (dbg != _dbgKey) {
      _dbgKey = dbg;
      debugPrint(
        '[dm-board] size=${size.width.toStringAsFixed(0)}x'
        '${size.height.toStringAsFixed(0)} blank=${blank.toStringAsFixed(0)} '
        'align=$align n=${_board.length}',
      );
    }
    // 只吃画面剩下的黑边：放不下字就不画（宁可没有，也别压住画面）
    if (blank < 72 || _board.isEmpty) return const SizedBox.shrink();
    final side = const BorderSide(color: Colors.black, width: 1.0);
    return Align(
      alignment: boardOnRight ? Alignment.centerRight : Alignment.centerLeft,
      child: SizedBox(
        width: blank,
        height: size.height,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              left: boardOnRight ? side : BorderSide.none,
              right: boardOnRight ? BorderSide.none : side,
            ),
          ),
          child: ListView.builder(
            // 倒序：新留言永远贴着底部进来，像直播间那样往上顶
            reverse: true,
            padding: EdgeInsets.zero,
            itemCount: _board.length,
            itemBuilder: (_, index) {
              final item = _board[_board.length - 1 - index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFCCCCCC), width: 1.0),
                  ),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: item.content),
                      if (item.dup > 1)
                        TextSpan(
                          text: '  ×${item.dup}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF666666),
                          ),
                        ),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: Colors.black,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    playerController
      ..removePositionListener(videoPositionListen)
      ..removeStatusLister(playerListener);
    _plDanmakuController.dispose();
    _boardTimer?.cancel();
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
          _startBoardTimer();
          // DanmakuScreen 会被销毁并 dispose 掉 canvas 的 controller，这里必须
          // 把播放器上的引用一起清掉，否则发弹幕等逻辑会拿到已释放的对象。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            playerController.danmakuController = null;
          });
        } else {
          // 回到居中：板上的留言一并丢掉，别留着过期内容
          _boardTimer?.cancel();
          _boardTimer = null;
          _board.clear();
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
  const _BoardDanmaku({
    required this.content,
    required this.dup,
    required this.expireAt,
  });
  final String content;

  /// 同一句被刷了几次
  final int dup;
  final DateTime expireAt;
}
