import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
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

  /// 播放器底色（PLVideoPlayer.fill）。留白那一侧就是这个颜色，
  /// 队列文字按它的明暗自适应 —— 这是白色底，写白字等于什么都没写。
  final Color fill;

  const PlDanmaku({
    super.key,
    required this.cid,
    required this.playerController,
    this.isPipMode = false,
    required this.isFullScreen,
    required this.isFileSource,
    required this.size,
    this.fill = Colors.white,
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
  // 画面缩到一侧后，另一侧空出来的留白里按直播留言板的方式一条条往下排，
  // 长句自己折行，每条按时长自然消失（不留时间轴）。
  final List<_BoardDanmaku> _board = [];
  /// 队列版本号：Obx 订阅它，任何增删都靠它把重绘打出去
  final RxInt _boardVer = 0.obs;
  /// 队列里最多留这么多条（真正显示几条由留白高度决定，见 _fitItems）
  static const int _maxKept = 120;
  Timer? _boardTimer;
  bool _boardAttached = false;
  /// 已经消费到哪个 100ms 桶，避免重复入队
  int _boardPos = -1;
  /// 上一次读到 / 正在显示的播放位置（仅用于排查）
  int _dbgPos = 0;
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
        // 队列由 _boardTimer 自己按桶消费，这里再塞一次会让同一句的
        // 重复计数翻倍，所以位置回调在队列模式下不参与。
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

  /// 把一批弹幕塞进队列。同一句刷屏就并成一条带次数，位置挪到最新，
  /// 避免整块板被一句话占满。返回是否真的变了。
  bool _pushAll(List<DanmakuElem> list) {
    final weight = DanmakuOptions.danmakuWeight;
    final now = DateTime.now();
    var changed = false;
    for (final e in list) {
      if (e.weight < weight) continue;
      final content = e.content.trim();
      if (content.isEmpty) continue;
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
    if (!changed) return false;
    if (_board.length > _maxKept) {
      _board.removeRange(0, _board.length - _maxKept);
    }
    return true;
  }

  /// 队列有任何变化都从这里把重绘打出去（版本号 + setState 双保险：
  /// 只依赖 setState 时，Obx 内部的缓存有可能让子树的旧内容留在屏幕上）。
  void _bump() {
    if (!mounted) return;
    _boardVer.value++;
    setState(() {});
  }

  /// 队列的驱动：自己按 100ms 桶顺序取，不依赖播放器位置回调的节流
  /// （位置流十几帧才来一次，回调里只取当前桶会漏掉中间桶）。
  void _startBoardTimer() {
    _boardPos = playerController.positionInMilliseconds ~/ 100;
    _boardTimer ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _boardTick(),
    );
  }

  void _boardTick() {
    if (!mounted) return;
    if (!playerController.enableShowDanmaku.value) return;
    if (!playerController.showDanmaku && !widget.isPipMode) return;
    _dbgPos = playerController.positionInMilliseconds;
    var changed = false;
    if (playerController.playerStatus.isPlaying) {
      final bucket = _dbgPos ~/ 100;
      if (bucket > _boardPos) {
        // 拖进度时最多一次补 4s，别把整段弹幕一次灌进来
        final from = math.max(_boardPos + 1, bucket - 40);
        _boardPos = bucket;
        for (var b = from; b <= bucket; b++) {
          final list = _plDanmakuController.getCurrentDanmaku(b * 100);
          if (list == null || list.isEmpty) continue;
          changed = _pushAll(list) || changed;
        }
      }
      // 到点的自己退场；暂停时冻结，免得看画面时整块板被清空
      final now = DateTime.now();
      final before = _board.length;
      _board.removeWhere((e) => !e.expireAt.isAfter(now));
      if (_board.length != before) changed = true;
    }
    if (changed) _bump();
  }

  /// 视频显示宽高比。surface rect 是 syncPhysicalSurfaceSize 按 fit 算出来再
  /// 上屏的那块尺寸，比例就是画面上屏比例，优先用它；解码分辨率作退路。
  double? _videoAspect() {
    final rect = playerController.videoController?.rect.value;
    if (rect != null && rect.width > 0 && rect.height > 0) {
      return rect.width / rect.height;
    }
    final state = playerController.videoPlayerController?.state;
    final vw = state?.width ?? 0;
    final vh = state?.height ?? 0;
    if (vw > 0 && vh > 0) return vw / vh;
    return playerController.videoFit.value.aspectRatio;
  }

  /// 一条留言最多折几行（太长的刷屏句子不该占掉整列）
  static const int _maxLines = 6;

  /// 估算一条留言占多高：留白很窄，长句会折成好几行，行数按字宽算。
  /// 全角（汉字/假名/全角标点）按 1 个字宽，其余（英文数字）按 0.55 折算。
  double _rowEstimate(String content, int dup, double textW, double fontSize) {
    var units = 0.0;
    for (final r in content.runes) {
      units += r < 0x2E80 ? 0.55 : 1.0;
    }
    if (dup > 1) units += 2.5; // " ×12"
    final perLine = math.max(1.0, textW / fontSize);
    final lines = math.min(
      _maxLines,
      math.max(1, (units / perLine).ceil()),
    );
    return lines * fontSize * 1.22 + 4.8; // 上下 padding 4 + 分割线 0.8
  }

  /// 从队尾往回取，能塞进这块高度的都留下（多了从队头丢）。
  /// 高度是估的，宁可少塞一条也别溢出被裁掉半行。
  List<_BoardDanmaku> _fitItems(double textW, double fontSize, double height) {
    if (_board.isEmpty) return const [];
    final limit = height * 0.98;
    final out = <_BoardDanmaku>[];
    var used = 0.0;
    for (var i = _board.length - 1; i >= 0; i--) {
      final item = _board[i];
      final h = _rowEstimate(item.content, item.dup, textW, fontSize);
      if (used + h > limit && out.isNotEmpty) break;
      used += h;
      out.insert(0, item);
    }
    return out;
  }

  Widget _buildBoard(int ver) {
    final align = playerController.videoAlignment.value;
    // 画面贴左 → 空白在右；贴右 → 空白在左
    final boardOnRight = align == VideoAlignmentType.left;
    return LayoutBuilder(
      builder: (context, c) {
        final cw = c.maxWidth.isFinite ? c.maxWidth : widget.size.width;
        final ch = c.maxHeight.isFinite ? c.maxHeight : widget.size.height;
        // widget.size 在切全屏那一帧可能还是上一套尺寸，差太多就不采信
        final boxH = widget.size.height <= ch * 1.25
            ? math.max(widget.size.height, ch)
            : ch;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final ar = _videoAspect();
        final fit = playerController.videoFit.value.boxFit;
        // 这几种 fit 的宽度是铺满容器的，本来就没有单侧留白
        final fillsWidth =
            fit == BoxFit.fill || fit == BoxFit.cover || fit == BoxFit.fitWidth;
        // 和 FittedBox(fit: contain) 同一套：画面高度吃满容器，宽度按比例
        final arW = (fillsWidth || ar == null || ar <= 0 || !ar.isFinite)
            ? null
            : math.min(cw, boxH * ar);
        final rect = playerController.videoController?.rect.value;
        final rectW = rect == null ? 0.0 : rect.width / dpr;
        double videoW;
        if (fillsWidth) {
          videoW = cw;
        } else if (rectW > 0 &&
            rectW.isFinite &&
            rectW <= cw * 1.02 &&
            (arW == null || (rectW - arW).abs() <= cw * 0.06)) {
          videoW = rectW;
        } else if (arW != null) {
          videoW = arW;
        } else {
          videoW = cw;
        }
        // 单侧空白才是能写字的地方；画面铺满宽度就一个像素都不占
        var blank = (cw - videoW).clamp(0.0, cw).toDouble();
        if (!blank.isFinite) blank = 0;
        final fontSize = blank < 110
            ? 11.0
            : (blank < 200 ? 12.5 : 14.0);
        // 留白底色就是播放器底色：白底要写黑字，深色底才写白字
        final onLight = widget.fill.computeLuminance() > 0.5;
        final ink = onLight ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
        final inkSub = onLight
            ? const Color(0x99000000)
            : const Color(0x99FFFFFF);
        final lineColor = onLight
            ? const Color(0x33000000)
            : const Color(0x40FFFFFF);
        final items = _fitItems(blank - 12, fontSize, ch);
        final dbg = '${align.index}|${cw.round()}x${ch.round()}|'
            '${blank.round()}|${items.length}';
        if (dbg != _dbgKey) {
          _dbgKey = dbg;
          debugPrint(
            '[dm-board] align=$align box=${cw.round()}x${ch.round()} '
            'ar=$ar rectW=${rectW.round()} videoW=${videoW.round()} '
            'blank=${blank.round()} show=${items.length}/${_board.length} '
            'dpr=${dpr.toStringAsFixed(2)} fit=$fit v=$ver',
          );
        }
        // 排查用的一行小字：只在 debug 包里出现
        Widget mark() => Text(
          '留白${blank.round()} ${_dbgPos ~/ 1000}s '
          'n${items.length}/${_board.length}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 8, height: 1.2, color: inkSub),
        );
        if (blank < 48) {
          if (!kDebugMode) return const SizedBox.shrink();
          // 拿不到留白（fit 铺宽或 rect 还没上屏）时留个记号，便于定位
          return Align(
            alignment: Alignment.topCenter,
            child: Container(
              color: const Color(0x80000000),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'dm ${cw.round()}x${ch.round()} b${blank.round()} '
                '${_dbgPos ~/ 1000}s n${_board.length}',
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xCCFFFFFF),
                ),
              ),
            ),
          );
        }
        return Align(
          alignment:
              boardOnRight ? Alignment.centerRight : Alignment.centerLeft,
          child: SizedBox(
            width: blank,
            height: ch,
            // 不铺底板、不加边框：就写在画面空出来的那块里。
            // 从最上面往下排，新的接在末尾、按字数折行；
            // 一屏放不下就从队头丢掉最旧的 —— 纯队列，没有滚动。
            child: ClipRect(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty && kDebugMode) mark(),
                  for (final item in items)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: lineColor, width: 0.8),
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
                                  color: inkSub,
                                ),
                              ),
                          ],
                        ),
                        // 留白窄，长句要能折行，别被省略号截掉（最多 6 行）
                        softWrap: true,
                        maxLines: _maxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fontSize,
                          height: 1.22,
                          color: ink,
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
      // 订阅队列版本号：入队/过期都靠它把这一帧打出来
      final ver = _boardVer.value;
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
          _boardPos = -1;
        }
      }
      return AnimatedOpacity(
        opacity: playerController.enableShowDanmaku.value
            ? playerController.danmakuOpacity.value
            : 0,
        duration: const Duration(milliseconds: 100),
        // 画面对齐选了左/右：留着飞行弹幕会从贴边那侧飞出去，改成留言板列表
        child: board
            ? _buildBoard(ver)
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
