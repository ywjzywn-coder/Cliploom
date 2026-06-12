<p align="center">
  <img src="PasteBox/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="132" alt="Cliploom 图标">
</p>

<h1 align="center">Cliploom</h1>

<p align="center">
  轻量、原生、本地优先的 macOS 剪贴板与截图工具
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white">
  <img alt="Native App" src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0A84FF">
  <img alt="Local Only" src="https://img.shields.io/badge/Data-Local%20Only-34C759">
</p>

<p align="center">
  <a href="#核心功能">核心功能</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#权限说明">权限说明</a> ·
  <a href="#开发与测试">开发与测试</a> ·
  <a href="WINDOWS_PORT.md">Windows 接力</a>
</p>

---

Cliploom 常驻菜单栏，用 `Option+V` 打开剪贴板历史，用 `Option+A`
启动清晰、快速的原生截图。文本、链接、图片和文件记录都只保存在本机，
截图 OCR 与二维码识别也完全在本地完成。

## 核心功能

| 剪贴板 | 截图 |
| --- | --- |
| 文本、链接、图片、文件自动分类 | 窗口识别与自由框选 |
| 搜索、收藏、删除与键盘导航 | 矩形、箭头、画笔、文字与马赛克 |
| 重复内容自动置顶，不重复保存 | 原始像素 PNG 输出 |
| 恢复原应用并直接粘贴 | 本地 OCR 与二维码/条形码识别 |
| 面板位置记忆与多屏适配 | OCR 图片/文字分栏与比例记忆 |
| 最多保留 500 条或 30 天 | 结果窗口可被下一次截图自动替换 |

### 设计原则

- **原生轻量**：SwiftUI、AppKit、SwiftData、Vision 与 ScreenCaptureKit，无第三方运行时依赖。
- **本地优先**：不联网、不上传剪贴板、截图、OCR 或扫码内容。
- **随时可控**：支持暂停记录、清空历史、关闭开机启动和修改全局快捷键。
- **权限降级**：未授予辅助功能权限时仍可复制内容，只是不自动模拟 `Command+V`。

## 快速开始

### 1. 打开工程

使用 Xcode 打开 `PasteBox.xcodeproj`，选择 `PasteBox` Scheme 和 `My Mac`。

成功标志：Xcode 左上角可以看到运行按钮，构建产物名称为 `Cliploom`。
工程继续保留历史 Scheme、模块名和 Bundle ID，以兼容已有数据与测试。

### 2. 运行应用

按 `Command+R`，或者运行本地安装脚本：

```bash
zsh Scripts/install-local.sh
```

成功标志：菜单栏出现 Cliploom 图标，`/Applications/Cliploom.app` 已安装并打开。

本地脚本使用稳定的临时签名，适合当前 Mac 开发调试，但不能替代正式的
Developer ID 签名与 Apple 公证。

### 3. 验证剪贴板

1. 在任意应用复制一段文字。
2. 等待不超过 1 秒，按 `Option+V`。
3. 用方向键选择记录，按回车。

成功标志：最新内容位于第一条，并粘贴回先前使用的应用。

### 4. 验证截图

1. 按 `Option+A`。
2. 单击识别到的窗口，或拖动框选区域。
3. 直接回车完成，或使用工具栏标注、OCR、扫码和保存。

成功标志：PNG 已进入系统剪贴板，并出现在 Cliploom 的“图片”分类中。
点击 OCR 或扫码后，截图层会隐藏，只保留独立结果窗口。

## 权限说明

| 权限 | 用途 | 未授权时 |
| --- | --- | --- |
| 辅助功能 | 恢复目标应用并模拟 `Command+V` | 内容只复制到剪贴板 |
| 屏幕与系统音频录制 | 捕获屏幕与窗口 | 无法进入截图层 |

在“系统设置 > 隐私与安全性”中允许 Cliploom 后，返回应用刷新状态即可。
开发阶段如果应用签名身份发生变化，macOS 可能再次确认权限；正式分发必须使用固定
Bundle ID、Developer ID Application 签名并完成 Apple 公证。

## 数据与隐私

- SwiftData 历史库由 macOS 按现有 Bundle ID 管理。
- 图片缓存位于 `~/Library/Application Support/PasteBox/Images`。
- 文件记录只保存原路径，Cliploom 不复制、移动或删除用户原文件。
- 未收藏记录最多保留 500 条或 30 天，收藏记录不会自动清理。
- 所有识别和存储都在本机完成，项目不包含云同步、遥测或自动上传。

## 项目结构

```text
PasteBox/
├── App/          应用生命周期与菜单栏协调
├── Models/       SwiftData 剪贴板模型
├── Services/     监听、存储、热键、权限与粘贴
├── Screenshot/   捕获、选区、标注、OCR 与扫码
└── UI/           剪贴板面板、设置与原生视觉组件
PasteBoxTests/    分类、存储、截图、OCR、扫码与热键测试
Scripts/          本地安装和正式签名发布脚本
```

## 开发与测试

运行核心测试：

```bash
xcodebuild \
  -project PasteBox.xcodeproj \
  -scheme PasteBox \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/PasteBoxDerivedData \
  -only-testing:PasteBoxTests \
  test
```

成功标志：终端最后显示 `** TEST SUCCEEDED **`。

最低系统版本为 macOS 14，当前版本为 `0.1.0 Preview`。版本变化记录见
[CHANGELOG.md](CHANGELOG.md)。

## 发布

首个 GitHub Release 是源码预览版。当前仓库没有可用于公开分发的 Developer ID
证书，因此不会附带未经公证却伪装成正式版本的安装包。

查看 [Cliploom 0.1.0 Preview](https://github.com/ywjzywn-coder/Cliploom/releases/tag/v0.1.0)。

正式发布前，配置固定 Bundle ID、Developer ID Application 证书和 `notarytool`
凭据，然后运行：

```bash
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
NOTARY_KEYCHAIN_PROFILE='cliploom-notary' \
CLIPLOOM_BUNDLE_ID='你的固定反向域名.BundleID' \
./Scripts/release-macos.sh
```

成功标志：生成 `build/release/Cliploom-macOS.zip`，且签名、公证、Staple 与
Gatekeeper 检查全部通过。

## Windows 版本

Windows 端尚未开始实现。其他开发者或 Agent 可以直接从
[WINDOWS_PORT.md](WINDOWS_PORT.md) 接力，其中列出了行为基线、Windows API 映射、
模块接口、开发阶段和验收清单。目标不是逐行翻译 Swift，而是保持产品体验一致。
