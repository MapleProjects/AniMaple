import 'package:flutter/widgets.dart';
import 'player.dart';
import 'player.native.dart';
import 'widget.dart';

FittedBox showVideo(VideoController player, VideoView widget) {
  final w = player.videoSize.value.width;
  final h = player.videoSize.value.height;
  final effectiveW = (w > 0 && h > 0) ? w : 1920.0;
  final effectiveH = (w > 0 && h > 0) ? h : 1080.0;

  Widget video = Texture(
    textureId: (player as VideoControllerImplementation).id!,
  );
  if (player.orientation % 2 == 1 &&
      player.videoSize.value.height != player.videoSize.value.width) {
    video = OverflowBox(
      maxWidth: player.videoSize.value.height,
      minWidth: player.videoSize.value.height,
      maxHeight: player.videoSize.value.width,
      minHeight: player.videoSize.value.width,
      child: video,
    );
  }
  if (player.orientation > 0) {
    final flip = player.orientation > 3;
    final (a, b, c, d) = switch (player.orientation % 4) {
      1 => (0.0, 1.0, flip ? -1.0 : 1.0, 0.0),
      2 => (flip ? 1.0 : -1.0, 0.0, 0.0, -1.0),
      3 => (0.0, -1.0, flip ? -1.0 : 1.0, 0.0),
      _ => (0.0, 1.0, 1.0, 0.0),
    };
    video = Transform(
      transform: Matrix4(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1),
      alignment: .center,
      child: video,
    );
  }

  // Ocultar la línea verde provocada por relleno de macrobloques de decodificadores
  // hardware en Android TV (Amlogic/MediaTek) recortando los píxeles residuales del borde inferior.
  Widget content = ClipRect(
    child: SizedBox(
      width: effectiveW,
      height: effectiveH,
      child: OverflowBox(
        minWidth: effectiveW,
        maxWidth: effectiveW,
        minHeight: effectiveH + 6.0,
        maxHeight: effectiveH + 6.0,
        alignment: Alignment.topCenter,
        child: video,
      ),
    ),
  );

  if (player.subId != null && player.showSubtitle.value) {
    content = Stack(
      fit: StackFit.passthrough,
      children: [
        content,
        Texture(textureId: player.subId!),
      ],
    );
  }

  return FittedBox(
    fit: widget.videoFit,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(
      width: effectiveW,
      height: effectiveH,
      child: content,
    ),
  );
}
