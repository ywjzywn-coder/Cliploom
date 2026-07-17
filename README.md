<p align="center">
  <img src="PasteBox/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="128" alt="Cliploom app icon">
</p>

<h1 align="center">Cliploom</h1>

<p align="center">
  轻量、本地优先的 macOS 剪贴板与微信式截图工具。
</p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111111?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white">
  <img alt="Universal" src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-0A84FF">
  <img alt="Local Only" src="https://img.shields.io/badge/Data-Local%20Only-34C759">
</p>

<p align="center">
  <a href="#当前状态">当前状态</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#核心功能">核心功能</a> ·
  <a href="#截图工作流">截图工作流</a> ·
  <a href="#本地验证">本地验证</a> ·
  <a href="#权限与隐私">权限与隐私</a> ·
  <a href="#开发">开发</a>
</p>

---

## 项目定位

Cliploom 是一个常驻菜单栏的小工具，解决两个高频问题：

- 在 macOS 上用 `Option+V` 快速打开剪贴板历史。
- 像微信截图一样，用 `Option+A` 完成截图、标注、OCR、扫码、取色和保存。

它不是云剪贴板，也不做账号同步。所有剪贴板历史、截图、OCR 和扫码结果都保存在本机。

## 当前状态

Cliploom 的 macOS 版本已经进入功能稳定期。后续默认以修复 Bug、整理文档、
优化安装体验为主，不再主动扩展大功能。

| 项目 | 状态 |
| --- | --- |
| macOS 应用 | 可日常使用，最新源码以 `main` 分支为准 |
| 最新源码 | 已包含 2026-07-13 的截图完成、缩放裁剪和权限弹窗修复 |
| 最新安装包 | Releases 中的 `v1.1.1` DMG，可能落后于 `main` 最新源码 |
| 本地验证 | 见 [本地测试报告](docs/LOCAL_TEST_REPORT.md) |

> 如果你在 GitHub 上刷新 Releases 页面，只会看到最新安装包版本；
> 如果你刷新代码首页或 commit 列表，看到的是 `main` 分支最新源码。

## 快速开始

### 下载

前往 [Releases](https://github.com/ywjzywn-coder/Cliploom/releases) 下载最新 macOS 安装包。

当前稳定安装包：

```text
Cliploom-1.1.1-macOS-universal-unnotarized.dmg
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
| 快捷粘贴 | `Option+V` 打开面板，单击项目直接粘贴，方向键 + `Enter` 键盘粘贴 |
| 智能去重 | 相同内容再次复制时置顶，不重复堆积 |
| 图片缓存 | 图片保存到本机应用支持目录，文件记录只保存路径 |
| 自动清理 | 未收藏记录默认保留 500 条或 30 天，可在设置中自定义 |
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
| 粘贴选中项 | 单击 或 `Enter` |
| 启动截图 | `Option+A` |
| 确认截图 | 单击完成 或 `Enter` |
| 取消 / 关闭 | `Esc` 或鼠标右键 |
| 复制取色值 | `Command+C` |

剪贴板和截图快捷键都可以在设置中修改。

## 本地验证

最近一次本地验证时间：2026-07-17。

已验证内容：

- 截图工具栏命中区域不再在绘制周期中重建，确认按钮不再出现偶发无响应。
- 截图工具栏完成按钮会在命中区域尚未绘制缓存时正确触发。
- 工具栏空白边缘点击会归到最近的可用按钮，不再静默吞掉完成动作。
- `完成并复制` 有一次性提交保护；失败后可以重试，成功后关闭截图层。
- 缩放显示器、Retina 和选区靠近屏幕边缘时，裁剪像素不会越界。
- `Option+A` 截图完成后可以复制 PNG 到系统剪贴板。
- 剪贴板单击直接粘贴，右键弹出上下文菜单。
- 剪贴板粘贴延迟从 180ms 降至 100ms，感知更跟手。
- 剪贴板历史保留时长和条数支持设置项，默认仍为 30 天 / 500 条。
- 本地安装脚本可稳定更新 `/Applications/Cliploom.app` 并重新启动应用。
- 应用启动不会主动弹出辅助功能授权请求；只有用户点击"请求权限"才触发系统弹窗。
- 当前安装应用签名校验通过。

测试命令：

```bash
xcodebuild \
  -project PasteBox.xcodeproj \
  -scheme PasteBox \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PasteBoxTests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

成功标志：终端显示 `** TEST SUCCEEDED **`。

完整记录见 [docs/LOCAL_TEST_REPORT.md](docs/LOCAL_TEST_REPORT.md)。

## 权限与隐私

| 权限 | 用途 | 未授权时 |
| --- | --- | --- |
| 辅助功能 | 恢复原应用并模拟 `Command+V` | 只复制，需要手动粘贴 |
| 屏幕与系统音频录制 | 截图和窗口识别 | 无法启动截图 |

权限提示策略：

- Cliploom 启动时只静默刷新授权状态，不会主动弹辅助功能授权窗口。
- 设置页和首次引导中的“请求权限”按钮才会触发系统授权弹窗。
- 本地开发安装使用固定证书 `Cliploom Local Development`，并尽量保留 `/Applications/Cliploom.app` 容器，减少覆盖安装后 macOS 重新询问权限的概率。
- 如果系统设置里显示已授权但应用仍检测为未授权，通常是旧签名记录残留。移除旧的 Cliploom/PasteBox 权限项后重新添加一次即可。

数据策略：

- 剪贴板历史、截图、OCR 和扫码均在本机处理。
- 项目不包含网络上传、云同步或遥测代码。
- 图片缓存位于 `~/Library/Application Support/PasteBox/Images`。
- 文件记录只保存路径，不复制、移动或删除原文件。

覆盖安装新版本时，请保持路径为 `/Applications/Cliploom.app`，不要同时保留多个副本。
这样能最大程度减少 macOS 重新询问权限的概率。

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

脚本会：

- 使用或创建稳定的本地代码签名证书 `Cliploom Local Development`。
- 构建 Debug 版本。
- 保留 `/Applications/Cliploom.app` 这个容器并替换内部内容。
- 清理旧的 `/Applications/PasteBox.app`。
- 重新注册并启动 Cliploom。

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

## 维护状态

- macOS 版本：功能稳定，后续以维护为主。
- 最新变更：见 [CHANGELOG.md](CHANGELOG.md)。
