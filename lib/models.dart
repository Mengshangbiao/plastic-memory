import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';

String newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_ids++}';
int _ids = 0;
typedef Json = Map<String, dynamic>;

enum StoryNodeType { start, event, choice, random, ending }

extension NodeLabel on StoryNodeType {
  String get label => ['开幕', '事件', '选项', '乱数选择', '结局'][index];
  IconData get icon => [
    Icons.play_circle_outline,
    Icons.chat_bubble_outline,
    Icons.alt_route,
    Icons.shuffle,
    Icons.flag_outlined,
  ][index];
  Color get color => [calm, love, thought, fear, longing][index];
}

enum AssetCategory { bgm, click, voice, sound, background, character, item }

extension AssetLabel on AssetCategory {
  String get label => ['背景音', '点击音', '人物音', '特殊音效', '背景图', '人物图', '物品图'][index];
  bool get isImage => index >= 4;
  List<String> get extensions => isImage
      ? ['png', 'jpg', 'jpeg', 'webp', 'bmp']
      : ['mp3', 'wav', 'ogg', 'm4a', 'flac'];
}

class AssetEntry {
  AssetEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.path,
  });
  final String id, name, path;
  final AssetCategory category;
  Json toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'path': path,
  };
  factory AssetEntry.fromJson(Json j) => AssetEntry(
    id: j['id'] as String,
    name: j['name'] as String,
    category: AssetCategory.values.byName(j['category']),
    path: j['path'] as String,
  );
}

enum MotionType { transform, fade, swap }

extension MotionLabel on MotionType {
  String get label => ['变化', '隐藏', '差分'][index];
}

class StageMotion {
  StageMotion({
    required this.type,
    this.duration = 1,
    this.x = .2,
    this.y = .1,
    this.width = .25,
    this.height = .7,
    this.opacity = 0,
    this.assetId = '',
    this.soundId = '',
  });
  MotionType type;
  double duration, x, y, width, height, opacity;
  String assetId, soundId;
  Json toJson() => {
    'type': type.name,
    'duration': duration,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'opacity': opacity,
    'assetId': assetId,
    'soundId': soundId,
  };
  factory StageMotion.fromJson(Json j) => StageMotion(
    type: MotionType.values.byName(j['type']),
    duration: (j['duration'] as num).toDouble().clamp(.05, 120),
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    width: (j['width'] as num).toDouble(),
    height: (j['height'] as num).toDouble(),
    opacity: (j['opacity'] as num).toDouble().clamp(0, 1),
    assetId: j['assetId'] ?? '',
    soundId: j['soundId'] ?? '',
  );
}

class StageLayer {
  StageLayer({
    required this.id,
    required this.assetId,
    this.x = .35,
    this.y = .08,
    this.width = .3,
    this.height = .75,
    this.opacity = 1,
    this.action = '',
    List<StageMotion>? motions,
  }) : motions = motions ?? [];
  final String id;
  String assetId, action;
  double x, y, width, height, opacity;
  List<StageMotion> motions;
  StageLayer copy() => StageLayer.fromJson(toJson());
  void apply(StageMotion m) {
    switch (m.type) {
      case MotionType.transform:
        x = m.x;
        y = m.y;
        width = m.width;
        height = m.height;
      case MotionType.fade:
        opacity = m.opacity;
      case MotionType.swap:
        if (m.assetId.isNotEmpty) assetId = m.assetId;
    }
  }

  Json toJson() => {
    'id': id,
    'assetId': assetId,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'opacity': opacity,
    'action': action,
    'motions': motions.map((m) => m.toJson()).toList(),
  };
  factory StageLayer.fromJson(Json j) => StageLayer(
    id: j['id'],
    assetId: j['assetId'],
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    width: (j['width'] as num).toDouble(),
    height: (j['height'] as num).toDouble(),
    opacity: (j['opacity'] as num).toDouble().clamp(0, 1),
    action: j['action'] ?? '',
    motions: (j['motions'] as List? ?? [])
        .map((m) => StageMotion.fromJson(m))
        .toList(),
  );
}

class DialogueLine {
  DialogueLine({
    required this.id,
    this.speaker = '旁白',
    this.text = '',
    this.voiceAsset = '',
    this.textSpeed = 0,
    this.textSize = 0,
    this.bgmMode = 'inherit',
    this.bgmAsset = '',
    this.sceneEnabled = false,
    List<StageLayer>? layers,
  }) : layers = layers ?? [];
  final String id;
  String speaker, text, voiceAsset, bgmMode, bgmAsset;
  double textSpeed, textSize;
  bool sceneEnabled;
  List<StageLayer> layers;
  Json toJson() => {
    'id': id,
    'speaker': speaker,
    'text': text,
    'voiceAsset': voiceAsset,
    'textSpeed': textSpeed,
    'textSize': textSize,
    'bgmMode': bgmMode,
    'bgmAsset': bgmAsset,
    'sceneEnabled': sceneEnabled,
    'layers': layers.map((l) => l.toJson()).toList(),
  };
  factory DialogueLine.fromJson(Json j) => DialogueLine(
    id: j['id'],
    speaker: j['speaker'] ?? '旁白',
    text: j['text'] ?? '',
    voiceAsset: j['voiceAsset'] ?? '',
    textSpeed: (j['textSpeed'] as num? ?? 0).toDouble(),
    textSize: (j['textSize'] as num? ?? 0).toDouble(),
    bgmMode: j['bgmMode'] ?? 'inherit',
    bgmAsset: j['bgmAsset'] ?? '',
    sceneEnabled: j['sceneEnabled'] ?? false,
    layers: (j['layers'] as List? ?? [])
        .map((l) => StageLayer.fromJson(l))
        .toList(),
  );
}

class StoryNode {
  StoryNode({
    required this.id,
    required this.type,
    required this.title,
    required this.position,
    List<DialogueLine>? dialogue,
    List<String>? outgoing,
    List<String>? requiredChoices,
    this.choiceNumber = 0,
    this.prompt = '',
    this.backgroundAsset = '',
    this.backgroundBlur = false,
    this.bgmAsset = '',
    this.clickAsset = '',
  }) : dialogue = dialogue ?? [],
       outgoing = outgoing ?? [],
       requiredChoices = requiredChoices ?? [];
  final String id;
  final StoryNodeType type;
  String title, prompt, backgroundAsset, bgmAsset, clickAsset;
  Offset position;
  int choiceNumber;
  bool backgroundBlur;
  List<DialogueLine> dialogue;
  List<String> outgoing, requiredChoices;
  Json toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'x': position.dx,
    'y': position.dy,
    'dialogue': dialogue.map((l) => l.toJson()).toList(),
    'outgoing': outgoing,
    'requiredChoices': requiredChoices,
    'choiceNumber': choiceNumber,
    'prompt': prompt,
    'backgroundAsset': backgroundAsset,
    'backgroundBlur': backgroundBlur,
    'bgmAsset': bgmAsset,
    'clickAsset': clickAsset,
  };
  factory StoryNode.fromJson(Json j) => StoryNode(
    id: j['id'],
    type: StoryNodeType.values.byName(j['type']),
    title: j['title'],
    position: Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
    dialogue: (j['dialogue'] as List? ?? [])
        .map((l) => DialogueLine.fromJson(l))
        .toList(),
    outgoing: List<String>.from(j['outgoing'] ?? []),
    requiredChoices: List<String>.from(j['requiredChoices'] ?? []),
    choiceNumber: j['choiceNumber'] ?? 0,
    prompt: j['prompt'] ?? '',
    backgroundAsset: j['backgroundAsset'] ?? '',
    backgroundBlur: j['backgroundBlur'] ?? false,
    bgmAsset: j['bgmAsset'] ?? '',
    clickAsset: j['clickAsset'] ?? '',
  );
}

class ProjectModel {
  ProjectModel({
    required this.id,
    required this.name,
    required this.nodes,
    required this.startNodeId,
    List<String>? characters,
    List<AssetEntry>? assets,
    this.published = false,
    this.nextChoiceNumber = 1,
    this.dialogueSkin = '',
    this.choiceSkin = '',
    DateTime? updatedAt,
  }) : characters = characters ?? ['旁白'],
       assets = assets ?? [],
       updatedAt = updatedAt ?? DateTime.now();
  final String id;
  String name, startNodeId, dialogueSkin, choiceSkin;
  List<StoryNode> nodes;
  List<String> characters;
  List<AssetEntry> assets;
  bool published;
  bool isBuild = false;
  int nextChoiceNumber;
  DateTime updatedAt;
  StoryNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  AssetEntry? assetById(String id) {
    for (final a in assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  ProjectModel copy() => ProjectModel.fromJson(toJson());
  StoryNode addNode(StoryNodeType type, Offset position) {
    final node = StoryNode(
      id: newId(type.name),
      type: type,
      title: type.label,
      position: position,
    );
    if (type == StoryNodeType.choice) {
      node.choiceNumber = nextChoiceNumber++;
      node.title = '选项 ${node.choiceNumber}';
    }
    nodes.add(node);
    published = false;
    return node;
  }

  void removeNode(String id) {
    if (id == startNodeId) return;
    nodes.removeWhere((n) => n.id == id);
    for (final n in nodes) {
      n.outgoing.removeWhere((t) => t == id);
    }
    // Keep conditions referencing removed options visible to the validator;
    // silently deleting them would change the author's branching logic.
    published = false;
  }

  String? connectionError(StoryNode source, StoryNode target) {
    if (source.id == target.id) return '不能连接节点自身。';
    if (target.type == StoryNodeType.start &&
        source.type != StoryNodeType.event)
      return '只有事件可以连接回开幕；结局会自动返回开幕。';
    if (source.type == StoryNodeType.ending) return '结局只能被连接。';
    if (source.type == StoryNodeType.start &&
        target.type != StoryNodeType.event &&
        target.type != StoryNodeType.random)
      return '开幕只能连接一个事件或乱数选择。';
    if (source.type == StoryNodeType.random &&
        target.type != StoryNodeType.event)
      return '乱数选择只能连接事件。';
    if (source.outgoing.contains(target.id)) return '这条连线已经存在。';
    if ((source.type == StoryNodeType.start ||
            source.type == StoryNodeType.choice) &&
        source.outgoing.isNotEmpty)
      return '此节点只能有一个出口，请先移除原连线。';
    if (source.type == StoryNodeType.event &&
        source.outgoing.isNotEmpty &&
        (target.type != StoryNodeType.choice ||
            source.outgoing.any(
              (id) => nodeById(id)?.type != StoryNodeType.choice,
            )))
      return '事件可以连接多个同级选项，或一个其他节点。';
    return null;
  }

  String? connect(String sourceId, String targetId) {
    final source = nodeById(sourceId), target = nodeById(targetId);
    if (source == null || target == null) return '节点不存在。';
    final error = connectionError(source, target);
    if (error != null) return error;
    source.outgoing.add(target.id);
    if (target.type == StoryNodeType.choice) {
      final siblings = choiceGroup(target);
      final prompts = siblings.map((n) => n.prompt).where((s) => s.isNotEmpty);
      setChoicePrompt(target, prompts.isEmpty ? '' : prompts.first);
    }
    published = false;
    return null;
  }

  List<StoryNode> choiceGroup(StoryNode choice) {
    final ids = <String>{choice.id};
    bool changed;
    do {
      changed = false;
      for (final node in nodes.where((n) => n.type == StoryNodeType.event)) {
        if (node.outgoing.any(ids.contains)) {
          for (final id in node.outgoing) {
            if (nodeById(id)?.type == StoryNodeType.choice && ids.add(id))
              changed = true;
          }
        }
      }
    } while (changed);
    return nodes.where((n) => ids.contains(n.id)).toList();
  }

  void setChoicePrompt(StoryNode choice, String value) {
    for (final n in choiceGroup(choice)) {
      n.prompt = value;
    }
  }

  List<String> validate() {
    final issues = <String>[];
    final start = nodeById(startNodeId);
    if (start?.type != StoryNodeType.start ||
        nodes.where((n) => n.type == StoryNodeType.start).length != 1)
      issues.add('需要且只能有一个有效开幕节点。');
    if (nodes.map((n) => n.id).toSet().length != nodes.length)
      issues.add('存在重复节点编号。');
    if (!nodes.any((n) => n.type == StoryNodeType.ending))
      issues.add('请添加一个结局。');
    final reachable = <String>{};
    void visit(String id) {
      if (!reachable.add(id)) return;
      for (final next in nodeById(id)?.outgoing ?? <String>[]) {
        visit(next);
      }
    }

    if (start != null) visit(start.id);
    for (final node in nodes) {
      final prefix = node.type == StoryNodeType.choice
          ? '#${node.choiceNumber} ${node.title}'
          : node.title;
      if (!reachable.contains(node.id)) issues.add('$prefix 无法从开幕到达。');
      if (node.type != StoryNodeType.ending && node.outgoing.isEmpty)
        issues.add('$prefix 没有后续节点。');
      if (node.type == StoryNodeType.ending && node.outgoing.isNotEmpty)
        issues.add('$prefix 不能有出口。');
      if ((node.type == StoryNodeType.start ||
              node.type == StoryNodeType.choice) &&
          node.outgoing.length > 1)
        issues.add('$prefix 只能有一个出口。');
      if (node.type == StoryNodeType.random && node.outgoing.length < 2)
        issues.add('$prefix 至少需要连接两个事件。');
      if (node.type == StoryNodeType.event &&
          node.outgoing.length > 1 &&
          node.outgoing.any((id) => nodeById(id)?.type != StoryNodeType.choice))
        issues.add('$prefix 的多个出口必须全部是选项。');
      for (final id in node.outgoing) {
        final target = nodeById(id);
        if (target == null) {
          issues.add('$prefix 连接到了已删除的节点。');
          continue;
        }
        if ((target.type == StoryNodeType.start &&
                node.type != StoryNodeType.event) ||
            id == node.id)
          issues.add('$prefix 包含无效连线。');
        if (node.type == StoryNodeType.start &&
            target.type != StoryNodeType.event &&
            target.type != StoryNodeType.random)
          issues.add('开幕只能连接事件或乱数选择。');
        if (node.type == StoryNodeType.random &&
            target.type != StoryNodeType.event)
          issues.add('$prefix 只能连接事件。');
      }
      for (final id in node.requiredChoices) {
        if (nodeById(id)?.type != StoryNodeType.choice || id == node.id)
          issues.add('$prefix 的出现条件包含无效选项。');
      }
    }
    final canFinish = nodes
        .where((n) => n.type == StoryNodeType.ending)
        .map((n) => n.id)
        .toSet();
    bool changed;
    do {
      changed = false;
      for (final n in nodes) {
        if (n.outgoing.any(canFinish.contains) && canFinish.add(n.id))
          changed = true;
      }
    } while (changed);
    if (reachable.any((id) => !canFinish.contains(id)))
      issues.add('存在无法到达结局的路线，请检查循环或断开的出口。');
    return issues.toSet().toList();
  }

  Json toJson() => {
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'startNodeId': startNodeId,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'characters': characters,
    'assets': assets.map((a) => a.toJson()).toList(),
    'published': published,
    'nextChoiceNumber': nextChoiceNumber,
    'updatedAt': updatedAt.toIso8601String(),
    'dialogueSkin': dialogueSkin,
    'choiceSkin': choiceSkin,
  };
  factory ProjectModel.fromJson(Json j) {
    if (j['schemaVersion'] != 1) throw const FormatException('不支持的项目版本');
    return ProjectModel(
      id: j['id'],
      name: j['name'],
      startNodeId: j['startNodeId'],
      nodes: (j['nodes'] as List).map((n) => StoryNode.fromJson(n)).toList(),
      characters: List<String>.from(j['characters'] ?? ['旁白']),
      assets: (j['assets'] as List? ?? [])
          .map((a) => AssetEntry.fromJson(a))
          .toList(),
      published: j['published'] ?? false,
      nextChoiceNumber: j['nextChoiceNumber'] ?? 1,
      updatedAt: DateTime.tryParse(j['updatedAt'] ?? ''),
      dialogueSkin: j['dialogueSkin'] ?? '',
      choiceSkin: j['choiceSkin'] ?? '',
    );
  }
  factory ProjectModel.empty(String name) {
    final id = newId('project'), start = newId('start');
    return ProjectModel(
      id: id,
      name: name,
      startNodeId: start,
      nodes: [
        StoryNode(
          id: start,
          type: StoryNodeType.start,
          title: '开幕',
          position: const Offset(700, 420),
        ),
      ],
    );
  }
  factory ProjectModel.demo() {
    final p = ProjectModel.empty('樱花树下的约定');
    p.characters.addAll(['雨宫澪', '白石遥']);
    final intro = p.addNode(StoryNodeType.event, const Offset(1020, 420))
      ..title = '樱花树下';
    intro.dialogue.addAll([
      DialogueLine(id: newId('line'), text: '春天的风吹过校园，记忆像花瓣一样落在掌心。'),
      DialogueLine(id: newId('line'), speaker: '雨宫澪', text: '你还记得我们第一次见面的地方吗？'),
    ]);
    final a = p.addNode(StoryNodeType.choice, const Offset(1320, 300))
      ..title = '我记得。'
      ..prompt = '你想怎样回答？';
    final b = p.addNode(StoryNodeType.choice, const Offset(1320, 550))
      ..title = '我想再听你说一次。'
      ..prompt = a.prompt;
    final endA = p.addNode(StoryNodeType.ending, const Offset(1610, 300))
      ..title = '晴朗结局';
    endA.dialogue.add(
      DialogueLine(id: newId('line'), text: '有些回忆不会褪色，它们只是等待再次被想起。'),
    );
    final endB = p.addNode(StoryNodeType.ending, const Offset(1610, 550))
      ..title = '温柔结局';
    endB.dialogue.add(
      DialogueLine(
        id: newId('line'),
        speaker: '雨宫澪',
        text: '那就从现在开始，把新的回忆交给我吧。',
      ),
    );
    p.connect(p.startNodeId, intro.id);
    p.connect(intro.id, a.id);
    p.connect(intro.id, b.id);
    p.connect(a.id, endA.id);
    p.connect(b.id, endB.id);
    p.published = true;
    return p;
  }
}

class AppSettings {
  double master = .85,
      bgm = .7,
      voice = .9,
      sound = .75,
      textSpeed = 32,
      textSize = 22;
  bool fullscreen = false;
  Json toJson() => {
    'master': master,
    'bgm': bgm,
    'voice': voice,
    'sound': sound,
    'textSpeed': textSpeed,
    'textSize': textSize,
    'fullscreen': fullscreen,
  };
  factory AppSettings.fromJson(Json j) {
    final s = AppSettings();
    s.master = (j['master'] as num? ?? .85).toDouble().clamp(0, 1);
    s.bgm = (j['bgm'] as num? ?? .7).toDouble().clamp(0, 1);
    s.voice = (j['voice'] as num? ?? .9).toDouble().clamp(0, 1);
    s.sound = (j['sound'] as num? ?? .75).toDouble().clamp(0, 1);
    s.textSpeed = (j['textSpeed'] as num? ?? 32).toDouble().clamp(5, 100);
    s.textSize = (j['textSize'] as num? ?? 22).toDouble().clamp(14, 36);
    s.fullscreen = j['fullscreen'] ?? false;
    return s;
  }
  AppSettings();
}

/// Branch traversal is independent of rendering and audio.
class StorySession {
  StorySession(this.project, {math.Random? random})
    : random = random ?? math.Random(),
      nodeId = project.startNodeId;
  final ProjectModel project;
  final math.Random random;
  String nodeId;
  int lineIndex = 0;
  Set<String> selectedChoices = {};
  List<StoryNode> options = [];
  String? error;
  StoryNode get node => project.nodeById(nodeId)!;
  DialogueLine? get line =>
      lineIndex < node.dialogue.length ? node.dialogue[lineIndex] : null;
  bool get isMenu => node.type == StoryNodeType.start;

  Json checkpoint() => {
    'nodeId': nodeId,
    'lineId': line?.id,
    'selectedChoices': selectedChoices.toList(),
    'waitingForChoice': options.isNotEmpty,
  };

  /// Validate the complete position before changing the live session. Stable
  /// line IDs permit text edits/reordering without silently loading another line.
  void restore(Json saved) {
    final restoredNode = project.nodeById(saved['nodeId'] as String);
    final selected = (saved['selectedChoices'] as List).cast<String>().toSet();
    final waiting = saved['waitingForChoice'] as bool;
    final lineId = saved['lineId'] as String?;
    if (restoredNode == null ||
        ![
          StoryNodeType.event,
          StoryNodeType.ending,
        ].contains(restoredNode.type) ||
        selected.any(
          (id) => project.nodeById(id)?.type != StoryNodeType.choice,
        )) {
      throw const FormatException('存档对应的剧情已发生变化，请重新开始');
    }
    final index = lineId == null
        ? 0
        : restoredNode.dialogue.indexWhere((line) => line.id == lineId);
    if (index < 0 || (lineId == null && restoredNode.dialogue.isNotEmpty)) {
      throw const FormatException('存档中的对白已不存在，请重新开始');
    }
    final restoredOptions = <StoryNode>[];
    if (waiting) {
      if (restoredNode.type != StoryNodeType.event ||
          index < restoredNode.dialogue.length - 1 ||
          restoredNode.outgoing.isEmpty) {
        throw const FormatException('存档中的选项状态无效');
      }
      for (final id in restoredNode.outgoing) {
        final choice = project.nodeById(id);
        if (choice == null || choice.type != StoryNodeType.choice) {
          throw const FormatException('存档中的选项路线已发生变化');
        }
        if (choice.requiredChoices.every(selected.contains))
          restoredOptions.add(choice);
      }
      if (restoredOptions.isEmpty) throw const FormatException('存档中没有可用选项');
    }
    nodeId = restoredNode.id;
    lineIndex = index;
    selectedChoices = selected;
    options = restoredOptions;
    error = null;
  }

  void restart() {
    nodeId = project.startNodeId;
    lineIndex = 0;
    selectedChoices.clear();
    options.clear();
    error = null;
  }

  void advance() {
    error = null;
    if (options.isNotEmpty) return;
    if (!isMenu && lineIndex + 1 < node.dialogue.length) {
      lineIndex++;
      return;
    }
    if (node.type == StoryNodeType.ending) {
      restart();
      return;
    }
    _follow(node.outgoing);
  }

  void _follow(List<String> ids) {
    if (ids.isEmpty) {
      error = '这一段还没有连接后续节点。';
      return;
    }
    final targets = ids.map(project.nodeById).toList();
    if (targets.any((n) => n == null)) {
      error = '路线中的节点已不存在，请返回编辑器检查。';
      return;
    }
    if (targets.every((n) => n!.type == StoryNodeType.choice)) {
      options = targets
          .cast<StoryNode>()
          .where((n) => n.requiredChoices.every(selectedChoices.contains))
          .toList();
      if (options.isEmpty) error = '当前没有满足条件的选项，请检查选项条件。';
      return;
    }
    var next = targets.first!;
    final visited = <String>{};
    while (next.type == StoryNodeType.random) {
      if (!visited.add(next.id) || next.outgoing.isEmpty) {
        error = '乱数路线存在循环或没有出口。';
        return;
      }
      final candidate = project.nodeById(
        next.outgoing[random.nextInt(next.outgoing.length)],
      );
      if (candidate == null) {
        error = '乱数路线的目标不存在。';
        return;
      }
      next = candidate;
    }
    if (next.type == StoryNodeType.start) {
      restart();
      return;
    }
    nodeId = next.id;
    lineIndex = 0;
  }

  void choose(StoryNode option) {
    if (!options.any((n) => n.id == option.id)) return;
    selectedChoices.add(option.id);
    options.clear();
    _follow(option.outgoing);
  }
}
