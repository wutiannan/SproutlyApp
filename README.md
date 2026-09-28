# 灵想（Sproutly）

## 打开方式

1. 使用 Xcode 16 或更新版本，双击 `Sproutly.xcodeproj`。
2. 选择 `Sproutly` Target，在 **Signing & Capabilities** 中选择自己的 Team；如 Bundle ID 冲突，改成唯一值。
3. 选择 iOS 17+ 的 iPhone 运行。AR、相机和语音功能需要真机，并按提示授权。

## 当前工程

- SwiftUI、ARKit、RealityKit、AVFoundation、Speech。
- 首页：世界球、KAKA 与入口导航。
- 音乐：五种情绪、动态背景、情绪球、音波和情绪乐卡。
- AR：情绪语音任务、植物放置与植物收集。
- 我的：成长记录、家长管理和本机数据授权。
- 运行资源位于 `Sproutly/Assets.xcassets`、`Audio`、`Fonts`、`MusicBackgrounds` 和 `HomeModels`。
- 音乐部分需要网络；AR、相机和语音流程请优先在真机验证。

`tools/` 仅用于素材转换与检查，不是 App 运行必需文件。
