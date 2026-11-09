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
  /// 当前板子高度能放几条（按行高估），超出就从队头丢掉
  int _cap = 12;
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
    if (_board.length > _cap) {
      _board.removeRange(0, _board.length - _cap);
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

  /// 视频宽高比，取不到可靠值时返回 null。
  /// 注意这个包会改写 surface 尺寸，rect/state 常常恒报 16:9，只当参考。
  double? _videoAspect() {
    final fit = playerController.videoFit.value;
    if (fit.aspectRatio != null) return fit.aspectRatio;
    final state = playerController.videoPlayerController?.state;
    final vw = state?.width ?? 0;
    final vh = state?.height ?? 0;
    if (vw > 0 && vh > 0) return vw / vh;
    final rect = playerController.videoController?.rect.value;
    if (rect != null && rect.width > 0 && rect.height > 0) {
      return rect.width / rect.height;
    }
    return null;
  }

  Widget _buildBoard() {
    final align = playerController.videoAlignment.value;
    // 画面贴左 → 空白在右；贴右 → 空白在左
    final boardOnRight = align == VideoAlignmentType.left;
    return LayoutBuilder(
      builder: (context, c) {
        final cw = c.maxWidth.isFinite ? c.maxWidth : widget.size.width;
        final ch = c.maxHeight.isFinite ? c.maxHeight : widget.size.height;
        final boxH = widget.size.height > ch ? widget.size.height : ch;
        final ar = _videoAspect();
        if (ar == null || ar <= 0) return const SizedBox.shrink();
        // 和 FittedBox(fit: contain) 同一套算法：画面高度吃满容器，宽度按比例
        final fit = playerController.videoFit.value.boxFit;
        double videoW = cw;
        if (fit == BoxFit.contain || fit == BoxFit.fitHeight) {
          final w = boxH * ar;
          videoW = w > cw ? cw : w;
        } else if (fit == BoxFit.fitWidth) {
          videoW = cw / ar > boxH ? boxH * ar : cw;
        }
        // 单侧空白才是能写字的地方；画面铺满宽度就一个像素都不占
        final blank = (cw - videoW).clamp(0.0, cw).toDouble();
        final fontSize = blank < 110
            ? 11.0
            : (blank < 200 ? 12.5 : 14.0);
        // 队列容量：这一列能摞下的条数，多的从队头丢
        final rowH = fontSize * 1.22 + 5;
        final cap = (ch / rowH).floor().clamp(1, 60);
        _cap = cap;
        final dbg = '${align.index}|${cw.round()}x${ch.round()}|'
            '${blank.round()}|$cap';
        if (dbg != _dbgKey) {
          _dbgKey = dbg;
          debugPrint(
            '[dm-board] align=$align box=${cw.round()}x${ch.round()} '
            'ar=$ar videoW=${videoW.round()} blank=${blank.round()} '
            'cap=$cap n=${_board.length}',
          );
        }
        if (blank < 48) return const SizedBox.shrink();
        final items = _board.length > cap
            ? _board.sublist(_board.length - cap)
            : _board;
        return Align(
          alignment:
              boardOnRight ? Alignment.centerRight : Alignment.centerLeft,
          child: SizedBox(
            width: blank,
            height: ch,
            // 不铺底板、不加边框：就写在画面空出来的那块里。
            // 新的从底部进来，旧的从顶部被挤出去 —— 纯队列，没有滚动。
            child: ClipRect(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0x40FFFFFF),
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: item.content),
                            if (item.dup > 1)
                              TextSpan(
                                text: ' ×${item.dup}',
                                style: TextStyle(
                                  fontSize: fontSize - 1.5,
                                  color: const Color(0x99FFFFFF),
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fontSize,
                          height: 1.22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
      // 全屏横屏时竖视频两侧才真有留白，所以这里不再排除全屏；
      // 是否显示由 _buildBoard 按真实空白宽度决定。
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
