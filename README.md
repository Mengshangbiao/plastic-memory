# 可塑性记忆

《可塑性记忆》是一个面向个人创作者的可视化 Galgame 创作工具原型。

当前原型使用 Flutter + Dart，优先支持 Windows 桌面端。它已经打通了首页、作品库、设置、流程图编辑、节点连接、对白编辑和测试运行的基本闭环。

## 运行环境

- Flutter 3.47.5
- Dart 3.13.4
- Visual Studio 2022 Community
- Windows SDK 10.0.26100.0

## 启动

在项目根目录执行：

```powershell
flutter pub get
flutter run -d windows
```

也可以在 VS Code 中选择 Windows 设备后按 F5 启动。

## 当前原型能力

- 樱花粉主题首页与四个主入口。
- 作品库中的示例项目和新建项目。
- 开幕、事件、选项、乱数选择、结局五类节点。
- 节点拖动、节点连接和流程检查。
- 事件对白、选项条件、背景图和背景音乐素材名编辑。
- 基础设置页：总音量、BGM、人物语音、音效、文字速度、文字大小和全屏选项。
- 测试播放器：对白推进、选项分支、条件变量、随机节点和结局回到开幕。

当前“保存”先保存到运行中的编辑会话；项目文件夹、素材导入、实际音频播放、演出时间线和存档系统会在下一阶段接入。

## Git

项目已经初始化 Git 仓库。首次提交前需要配置提交者身份：

```powershell
git config user.name "你的名字"
git config user.email "你的邮箱"
git add .
git commit -m "初始化可塑性记忆 Flutter 原型"
```
