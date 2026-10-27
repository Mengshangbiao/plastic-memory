import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plastic_memory/models.dart';
import 'package:plastic_memory/stage.dart';

void main() {
  test(
    'demo is a complete graph and serializes without losing authoring data',
    () {
      final project = ProjectModel.demo();
      final line = project.nodes
          .firstWhere((n) => n.type == StoryNodeType.event)
          .dialogue
          .first;
      line
        ..sceneEnabled = true
        ..voiceAsset = 'voice'
        ..textSize = 28
        ..textSpeed = 70
        ..bgmMode = 'replace'
        ..bgmAsset = 'music';
      line.layers.add(
        StageLayer(
          id: 'portrait',
          assetId: 'a',
          action: 'start',
          motions: [
            StageMotion(
              type: MotionType.transform,
              x: .8,
              duration: 2,
              soundId: 'step',
            ),
            StageMotion(type: MotionType.swap, assetId: 'b'),
            StageMotion(type: MotionType.fade, opacity: .2),
          ],
        ),
      );
      final restored = ProjectModel.fromJson(
        jsonDecode(jsonEncode(project.toJson())),
      );
      expect(restored.toJson(), project.toJson());
      expect(restored.validate(), isEmpty);
      restored.nodes.first.outgoing.clear();
      expect(project.nodes.first.outgoing, isNotEmpty);
    },
  );
  test('all newly created collections can be edited independently', () {
    final project = ProjectModel.empty('新故事');
    final event = project.addNode(StoryNodeType.event, Offset.zero);
    final ending = project.addNode(StoryNodeType.ending, Offset.zero);
    ending.dialogue.add(DialogueLine(id: 'last', text: '再见'));
    expect(project.connect(project.startNodeId, event.id), isNull);
    expect(project.connect(event.id, ending.id), isNull);
    project.removeNode(ending.id);
    expect(event.outgoing, isEmpty);
    expect(event.dialogue, isEmpty);
  });
  test(
    'start/event/ending/random connection rules match authoring requirements',
    () {
      final p = ProjectModel.empty('规则');
      final event = p.addNode(StoryNodeType.event, Offset.zero),
          event2 = p.addNode(StoryNodeType.event, Offset.zero);
      final choice = p.addNode(StoryNodeType.choice, Offset.zero),
          choice2 = p.addNode(StoryNodeType.choice, Offset.zero);
      final random = p.addNode(StoryNodeType.random, Offset.zero),
          ending = p.addNode(StoryNodeType.ending, Offset.zero);
      expect(p.connect(p.startNodeId, choice.id), isNotNull);
      expect(p.connect(p.startNodeId, event.id), isNull);
      expect(p.connect(p.startNodeId, random.id), isNotNull);
      expect(p.connect(event.id, choice.id), isNull);
      expect(p.connect(event.id, choice2.id), isNull);
      expect(p.connect(event.id, event2.id), isNotNull);
      expect(p.connect(event.id, p.startNodeId), isNotNull);
      expect(p.connect(event2.id, p.startNodeId), isNull);
      expect(p.connect(ending.id, event.id), isNotNull);
      expect(p.connect(random.id, ending.id), isNotNull);
      expect(p.connect(random.id, event.id), isNull);
      expect(p.connect(random.id, event2.id), isNull);
      expect(p.connect(choice.id, ending.id), isNull);
      expect(p.connect(choice.id, event2.id), isNotNull);
      expect(p.connect(choice.id, choice.id), isNotNull);
    },
  );
  test(
    'choice numbers never get reused and sibling prompts stay synchronized',
    () {
      final p = ProjectModel.demo();
      final choices = p.nodes
          .where((n) => n.type == StoryNodeType.choice)
          .toList();
      p.setChoicePrompt(choices.first, '新的共同提示');
      expect(choices.last.prompt, '新的共同提示');
      p.removeNode(choices.last.id);
      final added = p.addNode(StoryNodeType.choice, Offset.zero);
      expect(added.choiceNumber, 3);
      final event = p.nodes.firstWhere((n) => n.type == StoryNodeType.event);
      p.connect(event.id, added.id);
      expect(added.prompt, choices.first.prompt);
    },
  );
  test('conditions require every selected option and survive branching', () {
    final p = ProjectModel.empty('条件');
    final events = List.generate(
      3,
      (_) => p.addNode(StoryNodeType.event, Offset.zero),
    );
    final choices = List.generate(
      3,
      (_) => p.addNode(StoryNodeType.choice, Offset.zero),
    );
    final end = p.addNode(StoryNodeType.ending, Offset.zero);
    p.connect(p.startNodeId, events[0].id);
    for (var i = 0; i < 3; i++) {
      p.connect(events[i].id, choices[i].id);
      p.connect(choices[i].id, i < 2 ? events[i + 1].id : end.id);
    }
    choices[2].requiredChoices = [choices[0].id, choices[1].id];
    final session = StorySession(p);
    session.advance();
    session.advance();
    session.choose(choices[0]);
    session.advance();
    session.choose(choices[1]);
    session.advance();
    expect(session.options.map((n) => n.id), [choices[2].id]);
    session.choose(choices[2]);
    expect(session.node.type, StoryNodeType.ending);
    session.advance();
    expect(session.isMenu, isTrue);
    expect(session.selectedChoices, isEmpty);
    session.advance();
    session.advance();
    session.choose(choices[0]);
    session.advance();
    session.choose(choices[1]);
    session.selectedChoices.remove(choices[0].id);
    session.advance();
    expect(session.options, isEmpty);
    expect(session.error, contains('没有满足条件'));
  });
  test('random chooses only connected events and reaches each with a seeded source', () {
    final p = ProjectModel.empty('乱数');
    final random = p.addNode(StoryNodeType.random, Offset.zero);
    final a = p.addNode(StoryNodeType.event, Offset.zero),
        b = p.addNode(StoryNodeType.event, Offset.zero);
    p.connect(p.startNodeId, random.id);
    p.connect(random.id, a.id);
    p.connect(random.id, b.id);
    final session = StorySession(p, random: Random(42)), seen = <String>{};
    for (var i = 0; i < 40; i++) {
      session.restart();
      session.advance();
      seen.add(session.nodeId);
    }
    expect(seen, {a.id, b.id});
  });
  test('validator catches unreachable paths, missing targets, cycles, and deleted conditions', () {
    final p = ProjectModel.demo();
    final orphan = p.addNode(StoryNodeType.event, Offset.zero)..title = '孤立事件';
    expect(p.validate().join(), contains('孤立事件 无法从开幕到达'));
    p.removeNode(orphan.id);
    final choice = p.nodes.firstWhere((n) => n.type == StoryNodeType.choice);
    choice.requiredChoices.add('deleted-choice');
    choice.outgoing = ['missing'];
    final issues = p.validate().join();
    expect(issues, contains('已删除的节点'));
    expect(issues, contains('出现条件'));
    expect(issues, contains('无法到达结局'));
  });
  test(
    'motion sequence interpolates transform/fade/swap and preserves the source',
    () {
      final original = StageLayer(
        id: 'layer',
        assetId: 'initial',
        x: 0,
        y: 0,
        width: .2,
        height: .4,
        motions: [
          StageMotion(
            type: MotionType.transform,
            duration: 2,
            x: .6,
            y: .2,
            width: .4,
            height: .8,
          ),
          StageMotion(type: MotionType.fade, duration: 2, opacity: 0),
          StageMotion(type: MotionType.swap, duration: 1, assetId: 'smile'),
        ],
      );
      expect(stageAt([original], 1).single.x, closeTo(.3, .0001));
      expect(stageAt([original], 3).single.opacity, closeTo(.5, .0001));
      final finalState = stageAt([original], double.infinity).single;
      expect(finalState.x, .6);
      expect(finalState.opacity, 0);
      expect(finalState.assetId, 'smile');
      expect(finalState.motions, isEmpty);
      expect(stageDuration([original]), 5);
      expect(original.assetId, 'initial');
      expect(original.x, 0);
    },
  );
}
