import 'dart:io';

import 'package:flutter/material.dart';

import 'models.dart';
import 'palette.dart';
import 'storage.dart';

export 'palette.dart';

ThemeData memoryTheme() {
  const shape = RoundedRectangleBorder(borderRadius: memoryRadius);
  const outlinedShape = RoundedRectangleBorder(
    borderRadius: memoryRadius,
    side: BorderSide(color: hairline),
  );
  final button = ButtonStyle(
    animationDuration: memoryMotion,
    elevation: const WidgetStatePropertyAll(0),
    shape: const WidgetStatePropertyAll(shape),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)
          ? raisedSurface
          : surface,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? quietInk : ink,
    ),
    overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: .04)),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? hairline
            : states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
            ? accent
            : accent.withValues(alpha: .32),
      ),
    ),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI'],
    scaffoldBackgroundColor: paper,
    canvasColor: surface,
    disabledColor: quietInk,
    dividerColor: hairline,
    splashFactory: NoSplash.splashFactory,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      onPrimary: paper,
      primaryContainer: raisedSurface,
      onPrimaryContainer: ink,
      secondary: love,
      onSecondary: paper,
      secondaryContainer: raisedSurface,
      onSecondaryContainer: ink,
      tertiary: thought,
      onTertiary: paper,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: secondaryInk,
      surfaceContainerLowest: paper,
      surfaceContainerLow: surface,
      surfaceContainer: raisedSurface,
      surfaceContainerHigh: raisedSurface,
      surfaceContainerHighest: raisedSurface,
      outline: quietInk,
      outlineVariant: hairline,
      error: anger,
      onError: paper,
      surfaceTint: Colors.transparent,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 15, height: 1.7),
      bodyMedium: TextStyle(fontSize: 13, height: 1.5),
      bodySmall: TextStyle(fontSize: 11, color: secondaryInk),
      headlineMedium: TextStyle(fontWeight: FontWeight.w300, letterSpacing: .6),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w300,
        letterSpacing: .4,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: hairline)),
    ),
    cardTheme: const CardThemeData(
      color: surface,
      elevation: 0,
      shape: outlinedShape,
      margin: EdgeInsets.all(8),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: raisedSurface,
      elevation: 0,
      shape: outlinedShape,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: raisedSurface,
      elevation: 0,
      shape: outlinedShape,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: raisedSurface,
        borderRadius: memoryRadius,
        border: Border.fromBorderSide(BorderSide(color: hairline)),
      ),
      textStyle: TextStyle(color: ink, fontSize: 12),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: raisedSurface,
      contentTextStyle: TextStyle(color: ink),
      actionTextColor: accent,
      elevation: 0,
      shape: outlinedShape,
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button),
    elevatedButtonTheme: ElevatedButtonThemeData(style: button),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(shape),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? quietInk
              : states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
              ? accent
              : secondaryInk,
        ),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: surface,
      selectedColor: raisedSurface,
      side: BorderSide(color: hairline),
      shape: shape,
      labelStyle: TextStyle(color: ink, fontSize: 12),
    ),
    sliderTheme: const SliderThemeData(trackHeight: 2),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: paper,
      labelStyle: TextStyle(color: secondaryInk),
      hintStyle: TextStyle(color: secondaryInk),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: memoryRadius,
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: memoryRadius,
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: memoryRadius,
        borderSide: BorderSide(color: accent),
      ),
    ),
  );
}

/// A very low opacity wash; it never competes with text or imported artwork.
class MemoryAtmosphere extends StatelessWidget {
  const MemoryAtmosphere({
    super.key,
    required this.child,
    this.backgroundColor = paper,
  });
  final Widget child;
  final Color backgroundColor;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: backgroundColor),
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-.8, -.6),
                  radius: .9,
                  colors: [
                    sorrow.withValues(alpha: .04),
                    sorrow.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(.7, -.15),
                  radius: .8,
                  colors: [
                    love.withValues(alpha: .03),
                    love.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-.2, .9),
                  radius: .8,
                  colors: [
                    calm.withValues(alpha: .04),
                    calm.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

void notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String label = '名称',
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
          onSubmitted: maxLines == 1
              ? (value) {
                  if (value.trim().isNotEmpty)
                    Navigator.pop(context, value.trim());
                }
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty)
              Navigator.pop(context, controller.text.trim());
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // Route animations may still render the text field immediately after pop.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ??
    false;

class AssetSelect extends StatelessWidget {
  const AssetSelect({
    super.key,
    required this.project,
    required this.label,
    required this.value,
    required this.onChanged,
    this.category,
    this.imagesOnly = false,
    this.emptyLabel = '无',
  });
  final ProjectModel project;
  final String label, value, emptyLabel;
  final AssetCategory? category;
  final bool imagesOnly;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final assets = project.assets
        .where(
          (a) =>
              (category == null || a.category == category) &&
              (!imagesOnly || a.category.isImage),
        )
        .toList();
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${assets.length}'),
      initialValue: assets.any((a) => a.id == value) ? value : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: '', child: Text(emptyLabel)),
        ...assets.map(
          (a) => DropdownMenuItem(
            value: a.id,
            child: Text(a.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class ProjectImage extends StatelessWidget {
  const ProjectImage({
    super.key,
    required this.store,
    required this.project,
    required this.assetId,
    this.fit = BoxFit.contain,
  });
  final ProjectStore store;
  final ProjectModel project;
  final String assetId;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final File? file = store.assetFile(project, assetId);
    Widget missing() => const Center(
      child: Icon(Icons.broken_image_outlined, color: secondaryInk, size: 32),
    );
    return file == null
        ? missing()
        : Image.file(file, fit: fit, errorBuilder: (_, _, _) => missing());
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.width = 215,
  });
  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final double width;
  @override
  Widget build(BuildContext context) => Material(
    color: raisedSurface,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: memoryRadius,
      side: BorderSide(color: hairline),
    ),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: '收起$title',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 17),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    ),
  );
}
