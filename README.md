# Cliploom

Cliploom 是一个轻量的原生 macOS 剪贴板历史工具。它常驻菜单栏，按 `Option+V`
即可打开剪贴板面板，支持文本、链接、图片和文件。按 `Option+A` 可启动截图，
支持窗口识别、自由框选、标注、马赛克、本地 OCR 和扫码。

## 开始运行

### 第 1 步：打开工程

用 Xcode 打开 `PasteBox.xcodeproj`。

成功标志：Xcode 左上角显示可运行的 `PasteBox` Scheme，目标设备为 `My Mac`。
工程内部暂时保留原 Scheme 和模块名，用于兼容历史数据与测试；构建出的应用名称为 Cliploom。

### 第 2 步：运行应用

按 Xcode 顶部的运行按钮，或使用快捷键 `Command+R`。

成功标志：屏幕顶部菜单栏出现 Cliploom 图标，并弹出首次使用引导。

如果需要安装到“应用程序”并让辅助功能权限在本地更新之间保持稳定，请运行：

```bash
zsh Scripts/install-local.sh
```

第一次运行会复用项目已有的本地签名证书，并弹出一次 macOS 管理员确认框。
输入当前 Mac 登录密码并允许后，后续本地更新不再需要重复确认。

成功标志：`/Applications/Cliploom.app` 被更新并自动打开，签名更新后只需重新允许
一次“隐私与安全性 > 辅助功能”权限。

### 第 3 步：授予直接粘贴权限

1. 在引导页点击“请求权限”。
2. 如果系统没有自动勾选，点击“打开系统设置”。
3. 在“隐私与安全性 > 辅助功能”中允许 Cliploom。
4. 回到 Cliploom 点击“刷新状态”。

成功标志：引导页显示“已授权”。

没有授权时仍可使用历史记录，但选择内容后只会复制，需要手动按 `Command+V`。

### 第 4 步：测试核心功能

1. 在任意应用复制一段文本。
2. 等待不超过 1 秒。
3. 按 `Option+V`。
4. 用方向键选择记录，按回车。

成功标志：Cliploom 浮层出现在记忆的位置，刚复制的内容位于第一条，并粘贴回原应用。

### 第 5 步：使用截图

1. 按 `Option+A`。
2. 首次使用时，在“隐私与安全性 > 屏幕与系统音频录制”中允许 Cliploom。
3. 再按一次 `Option+A`，单击窗口或拖动框选区域。
4. 使用底部工具栏标注、马赛克、OCR、扫码或保存；按回车也可直接完成。

成功标志：截图被复制到系统剪贴板，并自动出现在 Cliploom 的“图片”分类中。

点击 OCR 或扫码后，截图层会立即隐藏，只显示独立结果窗口；关闭结果窗口即可结束本次截图。

## 数据位置

- SwiftData 历史库：由 macOS 根据原 Bundle ID 保存，改名后继续复用。
- 图片缓存：`~/Library/Application Support/PasteBox/Images`，该兼容目录不会自动迁移或删除。
- 文件记录只保存原文件路径，删除记录不会删除原文件。
- 未收藏记录最多保留 500 条或 30 天，收藏记录不会自动清理。

## 构建和测试

计划开发 Windows 版本时，请先阅读 [WINDOWS_PORT.md](WINDOWS_PORT.md)。其中包含平台 API
替代关系、推荐技术栈、开发顺序和验收基线，方便其他 Agent 从当前仓库继续开发。

下面的命令只会编译工程并在 `/tmp` 中生成构建缓存，不会修改系统权限：

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
