# Cliploom 项目交接文档

## 项目概述
Cliploom（原 PasteBox）是 macOS 剪贴板增强 + 截图工具（菜单栏应用）。支持截图翻译（WeChat 风格内联翻译）、截图 OCR、条形码扫描、颜色取色等功能。

## 项目信息
- **项目路径**: `/Volumes/512G外置硬盘/Ctrlvc`
- **Git 远程**: `git@github.com:ywjzywn-coder/Cliploom.git`
- **分支**: `main`
- **构建**: `xcodebuild -project PasteBox.xcodeproj -scheme PasteBox -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- **安装**: `./Scripts/install-local.sh`（编译到临时目录→签名→复制到 `/Applications/Cliploom.app`）
- **测试**: `xcodebuild ... test` (或带 `-only-testing:PasteBoxTests`)

## 架构

### 核心组件
- `PasteBox/Screenshot/ScreenshotCoordinator.swift` — 截图流程总协调
- `PasteBox/Screenshot/ScreenshotOverlayController.swift` — 截图覆层窗口控制 + 绘制（主要的 UI 渲染）
- `PasteBox/Screenshot/ScreenshotOverlayController.swift:TranslationOverlayState` — 翻译覆层状态管理
- `PasteBox/Screenshot/ScreenshotModels.swift` — 坐标映射、工具定义、翻译方向检测
- `PasteBox/Screenshot/TextRecognizer.swift` — 文字识别（Vision 框架 + ImageAnalyzer）
- `PasteBox/Screenshot/TranslationManager.swift` — Google Translate 免费端点

### 关键技术
- **截图捕获**: ScreenCaptureKit (`SCScreenshotManager.captureImage`)
- **文字识别**: Vision `VNRecognizeTextRequest` + ImageAnalyzer
- **翻译**: Google Translate 免费 API `translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=...&dt=t&q=...`
- **视图坐标**: `isFlipped = false`（底部原点，Y 轴向上）

## 翻译功能状态

### 当前实现
用户选中屏幕区域→识别文字→Google Translate 翻译→在截图窗口上叠加白色背景+译文文字。

### 🔴 当前 Bug：翻译内联显示——翻译结果只显示白屏，无文字

**现象**: 
- 选择区域→点击翻译→识别阶段正常→翻译完成后选区变成纯白背景但无文字
- 之前曾有原文和译文同时可见、文字被上半截断等问题

**问题根因**（按排查优先级）:
1. **翻译 API 返回空** — `TranslationManager.translateSingle` 所有 catch 都返回 `""`，如果网络请求失败（沙箱限制/无网络/API 被墙）则所有译文为空。`isTranslated = !translatedText.isEmpty` 为 false，回退到 `originalText`。若 `state.lines` 也被意外清空则显示白屏。
2. **文字绘制坐标问题** — `NSView.isFlipped = false`（底部原点），但 `NSAttributedString.draw(with:options:)` 从 rect 的视觉顶部（即 `rect.maxY` 在非翻转坐标中）开始绘制。如果 `boundingRect` 测量的高度比实际渲染小，文字顶部被裁。
3. **`CGRect.fill()` 行为** — 当前用 `selection.fill()` 填充白色背景，需确认在 `draw(_:)` 中是否正常工作。

### 之前的改动记录
1. **单行 pill 方式** — 每个文本行独立白色气泡，宽度覆盖整行 → 原文透出（气泡位置不对）
2. **Union rect 方式** — 所有行合并为一个白色背景块 → 白框覆盖全部内容
3. **`draw(at:)` 逐行基线方式** — 用 `draw(at:)` 逐行绘制 → 白屏无文字（baseline Y 计算错误）
4. **当前方式** — 所有译文 join 为一段，`boundingRect` 测量高度后用 `draw(with:options:)` 居中绘制 → 白屏

### 坐标系统关键点
```
NSView (isFlipped = false):
  ┌────────────────── maxY (视觉顶部，Y 值最大)
  │
  │                  ↑ Y 轴向上
  │
  └────────────────── minY (视觉底部，Y=0)
  
draw(with:rect:) → 文字从 rect.maxY（视觉顶部）往下画
draw(at:point)   → point 是基线位置（非翻转坐标中）
```

### Vision boundingBox 坐标系
- Vision 的 `boundingBox` 是归一化 (0~1) 坐标，**左下角为原点**，Y 向上
- 和 `isFlipped = false` 的 NSView 坐标系**一致**
- 直接映射: `viewY = selection.minY + boundingBox.minY * selection.height`

### 翻译方向检测
`ScreenshotTranslationDirection.targetIdentifier()`:
- 中文→英文: 返回 `"en"`
- 其他→中文: 返回 `"zh-CN"`（谷歌标识符，非 Apple 的 `zh-Hans`）

## 文件结构
```
PasteBox/
├── App/                      # App 生命周期
├── Screenshot/
│   ├── ScreenshotCoordinator.swift  # 截图流程协调
│   ├── ScreenshotOverlayController.swift  # 覆层窗口+绘制+翻译状态
│   ├── ScreenshotModels.swift       # 坐标映射/工具/翻译方向
│   ├── ScreenshotRenderer.swift     # 渲染导出
│   ├── TextRecognizer.swift         # 文字识别
│   ├── TranslationManager.swift     # Google Translate API
│   └── ScreenshotPixelSampler.swift # 取色器
├── Services/
│   ├── PasteCoordinator.swift       # 粘贴逻辑（延迟优化）
│   └── ClipboardMonitor.swift       # 剪贴板监听
├── UI/
│   ├── ClipboardPanelView.swift     # 剪贴板面板
│   └── ...
└── ...
PasteBoxTests/
└── ScreenshotFeatureTests.swift     # 截图功能测试
```

## 最近 Git 历史
- `372958a` — Inline screenshot translation with Google Translate (no popups, no downloads)
- `74ab138` — Fix screenshot Done button reliability, reduce paste latency, enable single-click paste

## 调试建议
- 在 `showTranslationLines` 中添加 `NSLog("translation result: \(translations)")` 确认翻译是否返回数据
- 在 `drawTranslationLines` 中添加一个有颜色的占位文本来验证绘制路径是否被执行
- 使用 `Network Link Conditioner` 或抓包确认 Google Translate API 请求是否成功
- 检查 App Sandbox 是否允许网络访问（默认 macOS 应用需要 `com.apple.security.network.client` 授权）
