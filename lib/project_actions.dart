import 'package:flutter/material.dart';

import 'models.dart';
import 'storage.dart';
import 'ui.dart';

class ProjectDeleteButton extends StatelessWidget {
  const ProjectDeleteButton({
    super.key,
    required this.project,
    required this.store,
    required this.onDeleted,
    this.isCurrent = false,
  });

  final ProjectModel project;
  final ProjectStore store;
  final VoidCallback onDeleted;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: project.isBuild ? '删除作品' : '删除项目',
    icon: const Icon(Icons.delete_outline, size: 20),
    onPressed: () async {
      final deleted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeleteProjectDialog(
          project: project,
          store: store,
          isCurrent: isCurrent,
        ),
      );
      if (deleted == true && context.mounted) onDeleted();
    },
  );
}

class _DeleteProjectDialog extends StatefulWidget {
  const _DeleteProjectDialog({
    required this.project,
    required this.store,
    required this.isCurrent,
  });
  final ProjectModel project;
  final ProjectStore store;
  final bool isCurrent;

  @override
  State<_DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<_DeleteProjectDialog> {
  bool busy = false;
  String? error;

  Future<void> _delete() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.deleteProject(widget.project);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '删除失败，请检查文件是否被占用、目录权限是否正常，然后重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.project.isBuild ? '删除作品？' : '删除项目？'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“${widget.project.name}”',
              style: const TextStyle(color: ink),
            ),
            const SizedBox(height: 16),
            Text(
              widget.project.isBuild
                  ? '将永久删除这个可游玩版本、游玩存档及其素材副本。创作草稿和原始素材文件会保留。'
                  : '将永久删除这个项目的创作草稿、测试存档、素材副本和保存备份。已创建的可游玩版本和原始素材文件会保留。',
            ),
            const SizedBox(height: 12),
            Text(widget.isCurrent ? '此操作无法撤销，删除后将返回首页。' : '此操作无法撤销。'),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error!, style: const TextStyle(color: anger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: anger,
            foregroundColor: paper,
          ),
          onPressed: busy ? null : _delete,
          child: Text(busy ? '正在删除…' : '确认删除'),
        ),
      ],
    ),
  );
}

class ProjectPickerResult {
  const ProjectPickerResult.open(this.project) : deletedCurrent = false;
  const ProjectPickerResult.deleted() : project = null, deletedCurrent = true;
  final ProjectModel? project;
  final bool deletedCurrent;
}

class ProjectPickerDialog extends StatefulWidget {
  const ProjectPickerDialog({
    super.key,
    required this.store,
    required this.drafts,
    required this.currentId,
  });
  final ProjectStore store;
  final List<ProjectModel> drafts;
  final String currentId;

  @override
  State<ProjectPickerDialog> createState() => _ProjectPickerDialogState();
}

class _ProjectPickerDialogState extends State<ProjectPickerDialog> {
  late final drafts = [...widget.drafts];

  void _open(ProjectModel project) =>
      Navigator.pop(context, ProjectPickerResult.open(project));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('打开创作项目'),
    content: SizedBox(
      width: 560,
      height: 360,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新建项目'),
            onTap: () => _open(ProjectModel.empty('未命名回忆')),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: drafts.length,
              itemBuilder: (context, index) {
                final draft = drafts[index];
                final current = draft.id == widget.currentId;
                return ListTile(
                  key: ValueKey('draft-${draft.id}'),
                  title: Text(
                    draft.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${draft.nodes.length} 个节点 · ${current ? '当前项目' : '本地项目'}',
                  ),
                  onTap: () => _open(draft),
                  trailing: ProjectDeleteButton(
                    key: ValueKey('delete-draft-${draft.id}'),
                    project: draft,
                    store: widget.store,
                    isCurrent: current,
                    onDeleted: () {
                      if (current) {
                        Navigator.pop(
                          this.context,
                          const ProjectPickerResult.deleted(),
                        );
                      } else {
                        setState(() => drafts.removeAt(index));
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
