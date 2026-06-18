<p align="center">
  <img src="PasteBox/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="128" alt="Cliploom app icon">
</p>

<h1 align="center">Cliploom</h1>

<p align="center">
  轻量、本地优先的 macOS 剪贴板与微信式截图工具。
  <br>
  目标是在 macOS 和 Windows 之间保持同一套复制、截图、OCR 与扫码操作逻辑。
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111111?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white">
  <img alt="Universal" src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-0A84FF">
  <img alt="Local Only" src="https://img.shields.io/badge/Data-Local%20Only-34C759">
  <img alt="Windows Port" src="https://img.shields.io/badge/Windows-Port%20Spec%20Ready-0078D4?logo=windows">
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="#核心功能">核心功能</a> ·
  <a href="#截图工作流">截图工作流</a> ·
  <a href="#权限与隐私">权限与隐私</a> ·
  <a href="#windows-接力开发">Windows 接力开发</a> ·
  <a href="#开发">开发</a>
</p>

---

## 项目定位

Cliploom 是一个常驻菜单栏的小工具，解决两个高频问题：

- 像 Windows `Win+V` 一样，在 macOS 上用 `Option+V` 打开剪贴板历史。
- 像微信截图一样，用 `Option+A` 完成截图、标注、OCR、扫码、取色和保存。

它不是云剪贴板，也不做账号同步。项目里的“跨设备同步”指的是同步操作习惯：
当你从 Mac 切到 Windows 时，仍然使用相同的快捷键思路、分类规则、确认/取消逻辑和截图流程。

## 快速开始

### 下载

前往 [Releases](https://github.com/ywjzywn-coder/Cliploom/releases) 下载最新 macOS 安装包。

当前稳定安装包：

```text
Cliploom-1.1.0-macOS-universal-unnotarized.dmg
```

成功标志：下载目录中出现 `.dmg` 文件。

### 安装

1. 双击打开 DMG。
2. 将 `Cliploom.app` 拖入 `Applications`。
3. 在“应用程序”中右键 Cliploom，选择“打开”。
4. 如果 macOS 提示无法验证开发者，在“系统设置 > 隐私与安全性”中选择“仍要打开”。

成功标志：菜单栏出现 Cliploom 图标。

详细步骤见 [安装指南](docs/INSTALL.md)。

> 当前 GitHub 版本是未公证安装包，所以会出现“无法验证开发者”的提示。
> 这是分发方式导致的，不代表应用会联网或上传数据。

## 核心功能

| 功能 | 说明 |
| --- | --- |
| 剪贴板历史 | 记录文本、链接、图片和文件，支持搜索、分类、收藏、删除 |
| 快捷粘贴 | `Option+V` 打开面板，方向键选择，`Enter` 粘贴 |
| 智能去重 | 相同内容再次复制时置顶，不重复堆积 |
| 图片缓存 | 图片保存到本机应用支持目录，文件记录只保存路径 |
| 自动清理 | 未收藏记录最多保留 500 条或 30 天 |
| 菜单栏控制 | 打开面板、截图、暂停记录、清空历史、设置、退出 |
| 本地优先 | 无云同步、无遥测、无自动上传 |

## 截图工作流

按 `Option+A` 进入截图：

1. 单击自动识别的窗口，或拖动框选自由区域。
2. 使用矩形、箭头、画笔、文字、马赛克进行标注。
3. 使用 OCR、二维码识别、取色器或保存。
4. 点击完成或按 `Enter`，PNG 会写入系统剪贴板并加入图片历史。

取消规则保持简单：

- 选区外单击取消。
- 鼠标右键取消。
- `Esc` 取消。

### OCR

框选后点击 OCR：

- 截图层会隐藏，只显示识别结果窗口。
- 左侧是可选中文字的图片预览，支持 macOS 原生 Live Text。
- 右侧是完整、可编辑的 OCR 文本。
- 中间分隔线可以拖动，比例会被记住。

### 二维码和条形码

框选后点击扫码：

- 图片预览会变暗，方便定位结果。
- HTTP/HTTPS 二维码中心显示动态圆形箭头，点击直接用默认浏览器打开。
- 非链接码或无法支持的码会显示禁止图标和说明。
- 多个二维码会分别显示多个标记。

### 取色器

截图时移动鼠标即可在指针旁看到颜色预览和 HEX 色值。
按 `Command+C` 可以复制当前色值。

## 快捷键

| 动作 | 默认快捷键 |
| --- | --- |
| 打开剪贴板 | `Option+V` |
| 启动截图 | `Option+A` |
| 确认 / 粘贴 | `Enter` |
| 取消 / 关闭 | `Esc` 或鼠标右键 |
| 复制取色值 | `Command+C` |

剪贴板和截图快捷键都可以在设置中修改。

## 权限与隐私

| 权限 | 用途 | 未授权时 |
| --- | --- | --- |
| 辅助功能 | 恢复原应用并模拟 `Command+V` | 只复制，需要手动粘贴 |
| 屏幕与系统音频录制 | 截图和窗口识别 | 无法启动截图 |

数据策略：

- 剪贴板历史、截图、OCR 和扫码均在本机处理。
- 项目不包含网络上传、云同步或遥测代码。
- 图片缓存位于 `~/Library/Application Support/PasteBox/Images`。
- 文件记录只保存路径，不复制、移动或删除原文件。

覆盖安装新版本时，请保持路径为 `/Applications/Cliploom.app`，不要同时保留多个副本。
这样能最大程度减少 macOS 重新询问权限的概率。

## Windows 接力开发

Windows 版本不是把 Swift 代码翻译一遍，而是复用产品行为，再使用 Windows 原生技术实现。

推荐方向：

- C# / .NET 8
- WinUI 3
- SQLite
- Windows Graphics Capture
- Windows OCR 或合适的本地 OCR 方案
- `RegisterHotKey` 管理全局快捷键

必须保持一致的行为：

| 操作 | macOS | Windows 目标 |
| --- | --- | --- |
| 打开剪贴板 | `Option+V` | `Alt+V` |
| 启动截图 | `Option+A` | `Alt+A` |
| 移动选择 | 方向键 | 方向键 |
| 确认 / 粘贴 | `Enter` | `Enter` |
| 取消 / 关闭 | 鼠标右键或 `Esc` | 鼠标右键或 `Esc` |
| 内容分类 | 文本、链接、图片、文件、收藏 | 相同 |
| 数据策略 | 本地存储、主动清理 | 相同 |

接力开发请从 [WINDOWS_PORT.md](WINDOWS_PORT.md) 开始。

## 开发

### macOS 技术栈

- Swift 5
- SwiftUI + AppKit
- SwiftData
- ScreenCaptureKit
- Vision / VisionKit
- Translation framework

### 本地运行

使用 Xcode 打开：

```text
PasteBox.xcodeproj
```

选择 `PasteBox` Scheme 和 `My Mac`，按 `Command+R` 运行。

成功标志：菜单栏出现 Cliploom 图标。

### 运行测试

```bash
xcodebuild \
  -project PasteBox.xcodeproj \
  -scheme PasteBox \
  -destination 'platform=macOS' \
  -only-testing:PasteBoxTests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

成功标志：终端显示 `** TEST SUCCEEDED **`。

### 本地安装

```bash
./Scripts/install-local.sh
```

成功标志：`/Applications/Cliploom.app` 被更新并重新启动。

## 打包

生成未公证预览 DMG：

```bash
./Scripts/package-preview.sh
```

成功标志：`build/preview` 中出现 DMG 和 `SHA256SUMS.txt`。

生成正式分发包需要 Developer ID Application 证书和 Apple 公证：

```bash
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
NOTARY_KEYCHAIN_PROFILE='cliploom-notary' \
CLIPLOOM_BUNDLE_ID='你的固定反向域名.BundleID' \
./Scripts/release-macos.sh
```

## 项目结构

```text
PasteBox/
├── App/          应用生命周期与菜单栏协调
├── Models/       SwiftData 剪贴板模型
├── Services/     监听、存储、热键、权限与粘贴
├── Screenshot/   捕获、选区、标注、OCR、扫码、取色与翻译
└── UI/           剪贴板面板、设置与原生视觉组件

PasteBoxTests/    核心行为测试
Scripts/          本地安装、预览打包和正式发布
docs/             安装与版本发布说明
Design/           图标与设计素材
```

## 状态

- macOS 版本：可用，持续完善体验。
- Windows 版本：已有接力设计规范，等待原生实现。
- 最新变更：见 [CHANGELOG.md](CHANGELOG.md)。
