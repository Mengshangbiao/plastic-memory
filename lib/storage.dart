import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'player_save.dart';

enum HomeEntrance { library, creation }

class ImportReport {
  final List<AssetEntry> imported = [];
  final List<String> errors = [];
}

class ProjectStore {
  ProjectStore(this.root);
  ProjectStore.memory() : root = null;
  final Directory? root;
  final Map<String, Json> _projects = {}, _games = {};
  final Map<String, Json> _playerSaves = {};
  final Set<String> _deleted = {};
  Json? _settings;
  final Map<HomeEntrance, DateTime> _visits = {};
  final List<String> warnings = [];
  Future<void> _writes = Future.value();
  static Future<ProjectStore> open() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'MemoryStudio'));
    await root.create(recursive: true);
    return ProjectStore(root);
  }

  String get location => root?.path ?? '测试会话';

  // Collection directories survive deletion of their last project, so an empty
  // library is not mistaken for a first launch and populated with the demo again.
  Future<bool> hasProjectHistory() async {
    if (root == null) {
      return _projects.isNotEmpty || _games.isNotEmpty || _deleted.isNotEmpty;
    }
    return await Directory(p.join(root!.path, 'projects')).exists() ||
        await Directory(p.join(root!.path, 'games')).exists();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _writes.catchError((Object _) {}).then((_) => action());
    _writes = operation;
    return operation;
  }

  // UI history is separate from story saves. Its filesystem modification time
  // records actual navigation, including visits that make no project edits.
  File _visitFile(HomeEntrance entrance) =>
      File(p.join(root!.path, 'entry-visits', '${entrance.name}.json'));

  Future<DateTime?> lastVisit(HomeEntrance entrance) async {
    if (root == null) return _visits[entrance];
    try {
      final stat = await _visitFile(entrance).stat();
      return stat.type == FileSystemEntityType.file ? stat.modified : null;
    } on FileSystemException {
      // Optional interface history must never prevent opening the project list.
      return null;
    }
  }

  Future<DateTime> recordVisit(HomeEntrance entrance) async {
    if (root == null) return _visits[entrance] = DateTime.now();
    final file = _visitFile(entrance);
    await _atomicWrite(file, {'entrance': entrance.name});
    return (await file.stat()).modified;
  }

  String _safeId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id))
      throw const FormatException('项目编号无效');
    return id;
  }

  Directory projectDirectory(ProjectModel project) => Directory(
    p.join(
      root!.path,
      project.isBuild ? 'games' : 'projects',
      _safeId(project.id),
    ),
  );
  File? assetFile(ProjectModel project, String assetId) {
    final asset = project.assetById(assetId);
    if (root == null || asset == null) return null;
    final base = projectDirectory(project).absolute.path;
    final path = p.normalize(p.join(base, asset.path));
    if (!p.isWithin(base, path)) return null;
    return File(path);
  }

  Future<List<ProjectModel>> loadProjects({bool games = false}) async {
    if (root == null)
      return (games ? _games : _projects).values
          .map(
            (j) =>
                ProjectModel.fromJson(jsonDecode(jsonEncode(j)))
                  ..isBuild = games,
          )
          .toList();
    final directory = Directory(
      p.join(root!.path, games ? 'games' : 'projects'),
    );
    if (!await directory.exists()) return [];
    final projects = <ProjectModel>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! Directory || p.basename(entry.path).startsWith('.'))
        continue;
      final file = File(p.join(entry.path, 'project.json'));
      if (!await file.exists()) continue;
      try {
        final model = ProjectModel.fromJson(
          jsonDecode(await file.readAsString()),
        );
        if (_safeId(model.id) != p.basename(entry.path))
          throw const FormatException('目录与项目编号不一致');
        model.isBuild = games;
        projects.add(model);
      } catch (_) {
        warnings.add(
          '${p.basename(entry.path)} 读取失败，原文件已保留；可检查 project.json.bak。',
        );
      }
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<void> _atomicWrite(File file, Json value) async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    if (await file.exists()) await file.copy('${file.path}.bak');
    await pending.rename(file.path);
  }

  Future<void> save(ProjectModel project) {
    project.updatedAt = DateTime.now();
    final id = _safeId(project.id), isBuild = project.isBuild;
    final snapshot = jsonDecode(jsonEncode(project.toJson())) as Json;
    return _enqueue(() async {
      // Ignore a late autosave or window-close save for an explicitly deleted copy.
      if (_deleted.contains('${isBuild ? 'games' : 'projects'}/$id')) return;
      await _writeSnapshot(id, isBuild, snapshot);
    });
  }

  Future<void> _writeSnapshot(String id, bool isBuild, Json snapshot) async {
    if (root == null) {
      (isBuild ? _games : _projects)[id] = snapshot;
      return;
    }
    await _atomicWrite(
      File(
        p.join(root!.path, isBuild ? 'games' : 'projects', id, 'project.json'),
      ),
      snapshot,
    );
  }

  /// Deletes only the selected draft or playable copy, including its own assets
  /// and backups. Imported source files and the other copy remain untouched.
  Future<void> deleteProject(ProjectModel project) => _enqueue(() async {
    final id = _safeId(project.id);
    final collection = project.isBuild ? 'games' : 'projects';
    if (root == null) {
      (project.isBuild ? _games : _projects).remove(id);
    } else {
      final target = projectDirectory(project).absolute;
      final type = await FileSystemEntity.type(target.path, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        final base = await root!.resolveSymbolicLinks();
        final expectedParent = p.join(base, collection);
        final parent = await target.parent.resolveSymbolicLinks();
        final resolved = await target.resolveSymbolicLinks();
        if (type != FileSystemEntityType.directory ||
            !p.equals(parent, expectedParent) ||
            !p.equals(resolved, p.join(expectedParent, id)) ||
            !p.isWithin(base, resolved)) {
          throw const FileSystemException('项目目录位置异常，未执行删除');
        }
        // Dart's recursive deletion removes nested links without following them.
        await Directory(resolved).delete(recursive: true);
      }
    }
    _deleted.add('$collection/$id');
    _playerSaves.removeWhere((key, _) => key.startsWith('$collection/$id/'));
  });

  String _playerSaveName(bool preview) =>
      preview ? 'preview-save.json' : 'play-save.json';
  String _playerSaveKey(ProjectModel project, bool preview) =>
      '${project.isBuild ? 'games' : 'projects'}/${_safeId(project.id)}/${_playerSaveName(preview)}';

  Future<void> savePlayerProgress(
    ProjectModel project,
    PlayerSave save, {
    bool preview = false,
  }) {
    save.validate(project);
    final key = _playerSaveKey(project, preview);
    final snapshot = jsonDecode(jsonEncode(save.toJson())) as Json;
    return _enqueue(() async {
      if (_deleted.contains(
        '${project.isBuild ? 'games' : 'projects'}/${project.id}',
      )) {
        throw StateError('该项目已删除，无法存档');
      }
      if (root == null) {
        _playerSaves[key] = snapshot;
      } else {
        await _atomicWrite(File(p.join(root!.path, key)), snapshot);
      }
    });
  }

  Future<PlayerSave?> loadPlayerProgress(
    ProjectModel project, {
    bool preview = false,
  }) async {
    await _writes.catchError((Object _) {});
    final key = _playerSaveKey(project, preview);
    Json? json;
    if (root == null) {
      final stored = _playerSaves[key];
      if (stored != null) json = jsonDecode(jsonEncode(stored)) as Json;
    } else {
      final file = File(p.join(root!.path, key));
      if (await file.exists())
        json = jsonDecode(await file.readAsString()) as Json;
    }
    if (json == null) return null;
    final save = PlayerSave.fromJson(json);
    save.validate(project);
    return save;
  }

  Future<AppSettings> loadSettings() async {
    if (root == null)
      return _settings == null
          ? AppSettings()
          : AppSettings.fromJson(_settings!);
    final file = File(p.join(root!.path, 'settings.json'));
    if (!await file.exists()) return AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      warnings.add('设置文件读取失败，本次使用默认设置；原文件已保留。');
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    if (root == null) {
      _settings = settings.toJson();
      return;
    }
    await _atomicWrite(
      File(p.join(root!.path, 'settings.json')),
      settings.toJson(),
    );
  }

  Future<ImportReport> importAssets(
    ProjectModel project,
    AssetCategory category,
    List<String> paths,
  ) async {
    final result = ImportReport();
    if (root == null) {
      result.errors.add('当前测试环境不支持导入。');
      return result;
    }
    final folder = Directory(
      p.join(projectDirectory(project).path, 'assets', category.name),
    );
    await folder.create(recursive: true);
    for (final path in paths) {
      final name = p.basename(path),
          ext = p.extension(path).toLowerCase().replaceFirst('.', '');
      if (!category.extensions.contains(ext)) {
        result.errors.add('$name：不支持此文件类型');
        continue;
      }
      try {
        final id = newId('asset');
        final relative = p.join('assets', category.name, '$id.$ext');
        await File(path).copy(p.join(projectDirectory(project).path, relative));
        final asset = AssetEntry(
          id: id,
          name: name,
          category: category,
          path: relative,
        );
        project.assets.add(asset);
        result.imported.add(asset);
      } catch (_) {
        result.errors.add('$name：无法读取或复制');
      }
    }
    if (result.imported.isNotEmpty) {
      project.published = false;
      await save(project);
    }
    return result;
  }

  Future<void> publish(ProjectModel project) => _enqueue(() async {
    final id = _safeId(project.id);
    if (_deleted.contains('projects/$id')) {
      throw StateError('该创作项目已删除');
    }
    final issues = project.validate();
    if (issues.isNotEmpty) throw StateError(issues.first);
    // A built game is a snapshot. Further edits never change the library copy.
    final build = project.copy()..published = true;
    if (root == null) {
      _games[project.id] = build.toJson();
    } else {
      final parent = Directory(p.join(root!.path, 'games'));
      await parent.create(recursive: true);
      final staging = Directory(p.join(parent.path, '.${newId('building')}'));
      await staging.create();
      try {
        for (final asset in project.assets) {
          final source = assetFile(project, asset.id);
          if (source == null || !await source.exists())
            throw FileSystemException('找不到素材：${asset.name}');
          final destination = File(p.join(staging.path, asset.path));
          if (!p.isWithin(staging.path, p.normalize(destination.path)))
            throw const FormatException('素材路径无效');
          await destination.parent.create(recursive: true);
          await source.copy(destination.path);
        }
        await _atomicWrite(
          File(p.join(staging.path, 'project.json')),
          build.toJson(),
        );
        final target = Directory(p.join(parent.path, _safeId(project.id)));
        // Republishing replaces the playable snapshot but preserves its tiny
        // checkpoint. Loading validates stable story IDs against the new version.
        for (final name in ['play-save.json', 'play-save.json.bak']) {
          final saved = File(p.join(target.path, name));
          if (await saved.exists())
            await saved.copy(p.join(staging.path, name));
        }
        final backup = Directory(
          p.join(parent.path, '.${project.id}-previous'),
        );
        if (await backup.exists()) await backup.delete(recursive: true);
        if (await target.exists()) await target.rename(backup.path);
        try {
          await staging.rename(target.path);
        } catch (_) {
          if (await backup.exists()) await backup.rename(target.path);
          rethrow;
        }
        if (await backup.exists()) await backup.delete(recursive: true);
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    }
    project.published = true;
    project.updatedAt = DateTime.now();
    await _writeSnapshot(id, false, project.toJson());
    _deleted.remove('games/$id');
  });
}
