# Cliploom 安装指南

本指南适用于从 GitHub 下载的未公证 Developer Preview 安装包。

## 1. 下载

1. 打开
   [Cliploom Releases](https://github.com/ywjzywn-coder/Cliploom/releases)。
2. 展开 `Cliploom 0.1.1 Developer Preview`。
3. 下载文件名包含 `macOS-universal-unnotarized.dmg` 的安装包。
4. 可以同时下载 `SHA256SUMS.txt` 校验文件。

成功标志：下载文件的后缀为 `.dmg`。

## 2. 安装

1. 双击 DMG。
2. 将 Cliploom 图标拖到 Applications 文件夹。
3. 等待复制完成后推出 DMG。

成功标志：在 Finder 的“应用程序”中可以看到 Cliploom。

## 3. 首次打开

由于安装包未经过 Apple 公证，直接双击可能会提示无法验证开发者。

1. 在 Finder 的“应用程序”中找到 Cliploom。
2. 按住 `Control` 点击 Cliploom，选择“打开”。
3. 在新提示中再次点击“打开”。

如果没有“打开”按钮：

1. 打开“系统设置”。
2. 进入“隐私与安全性”。
3. 向下找到 Cliploom 的安全提示。
4. 点击“仍要打开”。

成功标志：菜单栏出现 Cliploom 图标。

## 4. 授予辅助功能权限

这个权限用于自动把选中的历史内容粘贴回原应用。

1. 打开 Cliploom 设置。
2. 点击辅助功能权限旁的系统设置按钮。
3. 在“隐私与安全性 > 辅助功能”中开启 Cliploom。
4. 退出并重新打开 Cliploom。

成功标志：Cliploom 设置页显示辅助功能“已授权”。

没有授权时仍能使用剪贴板历史，但需要手动按 `Command+V`。

## 5. 授予屏幕录制权限

这个权限用于截图，不会上传屏幕内容。

1. 按 `Option+A`。
2. 按系统提示进入“隐私与安全性 > 屏幕与系统音频录制”。
3. 开启 Cliploom。
4. 退出并重新打开 Cliploom。

成功标志：再次按 `Option+A` 时进入截图界面。

## 6. 更新版本

1. 下载新版本 DMG。
2. 退出正在运行的 Cliploom。
3. 将新版 `Cliploom.app` 拖入 Applications。
4. 选择替换旧版本。

为了尽量保留系统权限：

- 始终安装到 `/Applications/Cliploom.app`。
- 不要重命名应用。
- 不要同时运行下载目录和 Applications 中的两个副本。

未公证版本无法保证 macOS 永远不会重新确认权限。如果系统再次询问，按照第 4、
第 5 步重新允许即可。

## 7. 校验下载文件

校验可以确认下载的 DMG 没有损坏。打开终端，进入下载目录后运行：

```bash
shasum -a 256 Cliploom-0.1.1-macOS-universal-unnotarized.dmg
```

成功标志：输出值与 Release 中 `SHA256SUMS.txt` 的值一致。
