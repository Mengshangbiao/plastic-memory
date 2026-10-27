import 'models.dart';

/// One small checkpoint: dialogue/branch position and the settled scene only.
/// Project data, media files and screenshots are never duplicated into a save.
class PlayerSave {
  PlayerSave({
    required this.projectId,
    required this.savedAt,
    required this.position,
    required this.layers,
    required this.background,
    required this.blur,
    required this.bgm,
  });

  final String projectId, background, bgm;
  final DateTime savedAt;
  final Json position;
  final List<StageLayer> layers;
  final bool blur;

  Json toJson() => {
    'version': 1,
    'projectId': projectId,
    'savedAt': savedAt.toIso8601String(),
    'position': position,
    'layers': layers.map((layer) => layer.toJson()).toList(),
    'background': background,
    'blur': blur,
    'bgm': bgm,
  };

  factory PlayerSave.fromJson(Json json) {
    if (json['version'] != 1) throw const FormatException('不支持此存档版本');
    return PlayerSave(
      projectId: json['projectId'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      position: Map<String, dynamic>.from(json['position'] as Map),
      layers: (json['layers'] as List)
          .map(
            (layer) =>
                StageLayer.fromJson(Map<String, dynamic>.from(layer as Map)),
          )
          .toList(),
      background: json['background'] as String,
      blur: json['blur'] as bool,
      bgm: json['bgm'] as String,
    );
  }

  void validate(ProjectModel project) {
    if (projectId != project.id) throw const FormatException('存档不属于这部作品');
    StorySession(project).restore(position);
    bool imageExists(String id) =>
        id.isEmpty || project.assetById(id)?.category.isImage == true;
    if (!imageExists(background) ||
        (bgm.isNotEmpty &&
            project.assetById(bgm)?.category != AssetCategory.bgm) ||
        layers.any(
          (layer) =>
              !imageExists(layer.assetId) ||
              layer.motions.isNotEmpty ||
              [
                layer.x,
                layer.y,
                layer.width,
                layer.height,
                layer.opacity,
              ].any((value) => !value.isFinite),
        )) {
      throw const FormatException('存档中的场景素材已变化或数据无效');
    }
  }
}
