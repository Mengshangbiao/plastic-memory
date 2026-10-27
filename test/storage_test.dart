import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plastic_memory/models.dart';
import 'package:plastic_memory/storage.dart';

void main() {
  late Directory sandbox;
  late ProjectStore store;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('memory_test_');
    store = ProjectStore(Directory(p.join(sandbox.path, 'library')));
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });
  test(
    'save and reopen recovers edits and retains the last saved backup',
    () async {
      final project = ProjectModel.demo();
      await store.save(project);
      project.name = '重命名的作品';
      await store.save(project);
      final reopened = (await ProjectStore(store.root).loadProjects()).single;
      expect(reopened.name, project.name);
      expect(reopened.nodes.length, project.nodes.length);
      final backup = File(
        p.join(store.projectDirectory(project).path, 'project.json.bak'),
      );
      expect(await backup.readAsString(), contains('樱花树下的约定'));
    },
  );
  test(
    'a bad project does not hide valid projects or replace the corrupt file',
    () async {
      final good = ProjectModel.demo(), bad = ProjectModel.empty('坏文件');
      await store.save(good);
      await store.save(bad);
      final file = File(
        p.join(store.projectDirectory(bad).path, 'project.json'),
      );
      await file.writeAsString('{bad');
      final loaded = await store.loadProjects();
      expect(loaded.map((p) => p.id), [good.id]);
      expect(store.warnings, hasLength(1));
      expect(await file.readAsString(), '{bad');
    },
  );
  test(
    'seven import categories copy files, keep names, and avoid collisions',
    () async {
      final project = ProjectModel.demo();
      for (final category in AssetCategory.values) {
        final source = File(
          p.join(sandbox.path, category.isImage ? '同名.png' : '同名.wav'),
        );
        await source.writeAsBytes([1, 2, 3, category.index]);
        final report = await store.importAssets(project, category, [
          source.path,
          source.path,
        ]);
        expect(report.errors, isEmpty);
        expect(report.imported, hasLength(2));
        expect(report.imported.first.path, isNot(report.imported.last.path));
        for (final asset in report.imported) {
          expect(asset.path, contains(category.name));
          expect(
            await store.assetFile(project, asset.id)!.readAsBytes(),
            await source.readAsBytes(),
          );
        }
        expect(await source.exists(), isTrue);
      }
      expect((await store.loadProjects()).single.assets, hasLength(14));
      final rejected = await store.importAssets(project, AssetCategory.bgm, [
        p.join(sandbox.path, '同名.png'),
      ]);
      expect(rejected.imported, isEmpty);
      expect(rejected.errors, hasLength(1));
    },
  );
  test(
    'published game is isolated from drafts and includes copied assets',
    () async {
      final project = ProjectModel.demo();
      final file = File(p.join(sandbox.path, '背景.png'));
      await file.writeAsBytes([10, 20]);
      final asset = (await store.importAssets(
        project,
        AssetCategory.background,
        [file.path],
      )).imported.single;
      await store.publish(project);
      project.name = '新的草稿';
      project.assets.clear();
      await store.save(project);
      await file.delete();
      final game = (await store.loadProjects(games: true)).single;
      expect(game.name, '樱花树下的约定');
      expect(game.isBuild, isTrue);
      expect(await store.assetFile(game, asset.id)!.readAsBytes(), [10, 20]);
    },
  );
  test('failed publish preserves the playable copy', () async {
    final project = ProjectModel.demo();
    await store.publish(project);
    project.assets.add(
      AssetEntry(
        id: 'missing',
        name: '不存在.png',
        category: AssetCategory.background,
        path: 'assets/background/missing.png',
      ),
    );
    await expectLater(
      store.publish(project),
      throwsA(isA<FileSystemException>()),
    );
    expect((await store.loadProjects(games: true)).single.assets, isEmpty);
  });
  test('asset paths cannot escape the project directory', () {
    final project = ProjectModel.demo();
    project.assets.add(
      AssetEntry(
        id: 'outside',
        name: 'outside',
        category: AssetCategory.background,
        path: '../../outside.png',
      ),
    );
    expect(store.assetFile(project, 'outside'), isNull);
  });
  test(
    'deleting a draft removes its backup and assets but preserves other copies',
    () async {
      final project = ProjectModel.demo();
      final other = ProjectModel.empty('保留项目');
      final source = File(p.join(sandbox.path, '原始素材.png'));
      await source.writeAsBytes([10, 20, 30]);
      final asset = (await store.importAssets(
        project,
        AssetCategory.background,
        [source.path],
      )).imported.single;
      await store.publish(project);
      await store.save(other);
      expect(
        await File(
          p.join(store.projectDirectory(project).path, 'project.json.bak'),
        ).exists(),
        isTrue,
      );
      await store.deleteProject(project);
      expect(await store.projectDirectory(project).exists(), isFalse);
      final reopened = ProjectStore(store.root);
      expect((await reopened.loadProjects()).map((p) => p.id), [other.id]);
      final game = (await reopened.loadProjects(games: true)).single;
      expect(await reopened.assetFile(game, asset.id)!.readAsBytes(), [
        10,
        20,
        30,
      ]);
      expect(await source.readAsBytes(), [10, 20, 30]);
    },
  );
  test(
    'deleting a playable copy preserves its draft and permits publishing again',
    () async {
      final draft = ProjectModel.demo();
      await store.publish(draft);
      final game = (await store.loadProjects(games: true)).single;
      await store.deleteProject(game);
      expect(await store.projectDirectory(game).exists(), isFalse);
      expect((await store.loadProjects()).single.id, draft.id);
      expect(await store.loadProjects(games: true), isEmpty);
      await store.save(game); // A stale save cannot resurrect the deleted copy.
      expect(await store.loadProjects(games: true), isEmpty);
      await store.publish(draft);
      expect((await store.loadProjects(games: true)).single.id, draft.id);
    },
  );
  test(
    'queued saves and window-close saves cannot recreate deleted drafts',
    () async {
      for (final target in [store, ProjectStore.memory()]) {
        final draft = ProjectModel.demo();
        final saving = target.save(draft);
        final deleting = target.deleteProject(draft);
        final staleSave = target.save(draft);
        await Future.wait([saving, deleting, staleSave]);
        expect(await target.loadProjects(), isEmpty);
        expect(await target.hasProjectHistory(), isTrue);
        await target.deleteProject(draft); // Repeated removal remains harmless.
        await expectLater(target.publish(draft), throwsStateError);
        final replacement = ProjectModel.empty('新项目');
        await target.save(replacement);
        expect((await target.loadProjects()).single.id, replacement.id);
      }
    },
  );
  test(
    'deletion waits for publication before removing the selected playable copy',
    () async {
      final draft = ProjectModel.demo();
      final game = draft.copy()..isBuild = true;
      final publishing = store.publish(draft);
      final deleting = store.deleteProject(game);
      await Future.wait([publishing, deleting]);
      expect(await store.loadProjects(games: true), isEmpty);
      expect((await store.loadProjects()).single.id, draft.id);
    },
  );
  test(
    'empty existing libraries are distinguishable from a first launch',
    () async {
      expect(await store.hasProjectHistory(), isFalse);
      final draft = ProjectModel.demo();
      await store.publish(draft);
      final game = (await store.loadProjects(games: true)).single;
      await store.deleteProject(draft);
      await store.deleteProject(game);
      final reopened = ProjectStore(store.root);
      expect(await reopened.hasProjectHistory(), isTrue);
      expect(await reopened.loadProjects(), isEmpty);
      expect(await reopened.loadProjects(games: true), isEmpty);
    },
  );
  test(
    'invalid deletion targets preserve files and do not poison later writes',
    () async {
      final victim = ProjectModel.empty('保留文件');
      await store.save(victim);
      final malformed = ProjectModel.fromJson({
        ...victim.toJson(),
        'id': '../outside',
      });
      await expectLater(store.deleteProject(malformed), throwsFormatException);
      final wrongType = ProjectModel.empty('目录被替换');
      final target = File(store.projectDirectory(wrongType).path);
      await target.writeAsString('keep');
      await expectLater(
        store.deleteProject(wrongType),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.readAsString(), 'keep');
      expect((await store.loadProjects()).single.id, victim.id);
      await target.delete();
      await store.save(wrongType);
      await store.deleteProject(wrongType);
      expect(await store.projectDirectory(wrongType).exists(), isFalse);
    },
  );
  test('settings persist all volume, text, and fullscreen fields', () async {
    final settings = AppSettings()
      ..master = .25
      ..bgm = .5
      ..voice = .2
      ..sound = .3
      ..textSize = 30
      ..textSpeed = 80
      ..fullscreen = true;
    await store.saveSettings(settings);
    expect(
      (await ProjectStore(store.root).loadSettings()).toJson(),
      settings.toJson(),
    );
  });
}
