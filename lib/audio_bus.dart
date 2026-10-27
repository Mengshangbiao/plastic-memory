import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'models.dart';
import 'storage.dart';

class AudioBus {
  AudioBus(this.project, this.store, this.settings, {required this.onError});
  final ProjectModel project;
  final ProjectStore store;
  final AppSettings settings;
  final void Function(String) onError;
  AudioPlayer? _bgm, _voice, _click;
  final Set<AudioPlayer> _effects = {};
  String currentBgm = '';
  String _playingBgm = '';
  int _generation = 0;
  Future<void> _queue = Future.value();
  bool disposed = false;
  // The player has no audio seek bar. Per-frame position polling would keep
  // the renderer running continuously even after a scene has finished moving.
  AudioPlayer _player() => AudioPlayer()..positionUpdater = null;
  Future<bool> _play(
    AudioPlayer player,
    String assetId,
    double volume, {
    bool loop = false,
    bool Function()? isCurrent,
  }) async {
    final file = store.assetFile(project, assetId);
    if (file == null || !await file.exists()) {
      onError('找不到音频素材，请返回检查导入文件。');
      return false;
    }
    if (disposed || isCurrent?.call() == false) return false;
    await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
    if (disposed || isCurrent?.call() == false) return false;
    await player.play(
      DeviceFileSource(file.path),
      volume: volume * settings.master,
    );
    return true;
  }

  void enter(
    StoryNode node,
    DialogueLine? line, {
    required bool nodeChanged,
    bool restart = false,
    bool silent = false,
  }) {
    var desired = restart ? '' : currentBgm;
    if (nodeChanged && node.bgmAsset.isNotEmpty) desired = node.bgmAsset;
    if (line?.bgmMode == 'replace') desired = line!.bgmAsset;
    if (line?.bgmMode == 'stop') desired = '';
    currentBgm = desired;
    _sync(silent ? '' : line?.voiceAsset ?? '');
  }

  void restore(String music, {String voice = ''}) {
    currentBgm = music;
    _sync(voice);
  }

  void stopSpeech() {
    _sync('');
    stopEffects();
  }

  void _sync(String voice) {
    final generation = ++_generation;
    if (store.root == null || disposed) return;
    final music = currentBgm;
    bool current() => !disposed && generation == _generation;
    _queue = _queue
        .then((_) async {
          // Fast-forward can enqueue several lines while a native player is
          // starting. Only apply the most recent line, avoiding an audio backlog.
          if (!current()) return;
          if (_playingBgm != music) {
            if (_bgm != null) await _bgm!.stop();
            _playingBgm = '';
            if (music.isNotEmpty && current()) {
              final played = await _play(
                _bgm ??= _player(),
                music,
                settings.bgm,
                loop: true,
                isCurrent: current,
              );
              // Even if superseded during play(), the next queued state must
              // know which track the native player may have started.
              if (played) _playingBgm = music;
            }
          }
          if (!current()) return;
          if (_voice != null) await _voice!.stop();
          if (voice.isNotEmpty && current())
            await _play(
              _voice ??= _player(),
              voice,
              settings.voice,
              isCurrent: current,
            );
        })
        .catchError((Object _) {
          if (!disposed) onError('音频播放失败，请检查素材格式。');
        });
  }

  Future<void> click(String id) async {
    if (id.isEmpty || store.root == null || disposed) return;
    try {
      await _play(_click ??= _player(), id, settings.sound);
    } catch (_) {
      if (!disposed) onError('点击音播放失败。');
    }
  }

  Future<void> effect(String id) async {
    if (id.isEmpty || store.root == null || disposed) return;
    final player = _player();
    _effects.add(player);
    player.onPlayerComplete.first
        .then((_) async {
          if (_effects.remove(player)) await player.dispose();
        })
        .catchError((Object _) {});
    try {
      final played = await _play(
        player,
        id,
        settings.sound,
        isCurrent: () => _effects.contains(player),
      );
      if (!played && _effects.remove(player)) await player.dispose();
    } catch (_) {
      if (_effects.remove(player)) {
        await player.dispose();
        if (!disposed) onError('演出音效播放失败。');
      }
    }
  }

  Future<void> stopEffects() async {
    final effects = _effects.toList();
    _effects.clear();
    for (final player in effects) {
      await player.dispose();
    }
  }

  Future<void> dispose() async {
    disposed = true;
    await _queue;
    for (final player in [_bgm, _voice, _click]) {
      if (player != null) await player.dispose();
    }
    await stopEffects();
  }
}
