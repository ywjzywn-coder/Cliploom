# Cliploom 本地测试报告

最后更新：2026-06-21  
测试机器：本机 macOS 开发环境  
功能验证基线：`4e896cd`

## 结论

Cliploom macOS 版本当前可作为日常自用版本。核心功能已经验证，后续项目默认进入
维护阶段：优先修复 Bug、更新文档和支持 Windows 接力开发，不再主动加入大功能。

## 已验证功能

| 模块 | 验证内容 | 结果 |
| --- | --- | --- |
| 剪贴板历史 | 文本、链接、图片、文件分类和去重 | 通过 |
| 历史清理 | 自定义保留条数和保留天数，非法值自动夹紧 | 通过 |
| 图片缓存 | 删除图片历史时同步清理缓存文件 | 通过 |
| 文件记录 | 删除历史不会删除用户原文件 | 通过 |
| 截图完成 | 工具栏命中区域未绘制缓存时点击完成仍触发复制 | 通过 |
| 截图取消 | 右键、Esc 和取消按钮都能退出截图 | 通过 |
| 截图渲染 | Retina / 缩放显示坐标转换和 PNG 尺寸 | 通过 |
| OCR | Vision / Live Text 回退路径和结果窗口 | 通过 |
| 二维码 | 多二维码、重复链接、非网页链接过滤 | 通过 |
| 取色器 | 指针取色、HEX 格式、边缘裁剪 | 通过 |
| 本地安装 | `/Applications/Cliploom.app` 更新并启动 | 通过 |
| 签名校验 | `codesign --verify` 校验当前安装应用 | 通过 |

## 最近运行的命令

### 单元测试

```bash
xcodebuild \
  -project PasteBox.xcodeproj \
  -scheme PasteBox \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:PasteBoxTests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

成功标志：

```text
** TEST SUCCEEDED **
```

### 样式检查

```bash
git diff --check
```

成功标志：命令无输出并以退出码 0 结束。

### 本地安装

```bash
./Scripts/install-local.sh
```

成功标志：

- `/Applications/Cliploom.app` 被更新。
- `pgrep -fl Cliploom` 能看到正在运行的 Cliploom 进程。

### 安装应用签名校验

```bash
codesign --verify --deep --strict --verbose=2 /Applications/Cliploom.app
```

成功标志：

```text
/Applications/Cliploom.app: valid on disk
/Applications/Cliploom.app: satisfies its Designated Requirement
```

## 已知测试限制

完整 `xcodebuild test` 会同时启动 UI Test Runner。最近一次完整测试里，
`PasteBoxUITests-Runner` 在建立 XCTest 连接前被系统 kill：

```text
PasteBoxUITests-Runner encountered an error
Early unexpected exit, operation never finished bootstrapping
```

同一轮里业务单元测试已经开始并通过；单独运行 `PasteBoxTests` 也通过。因此当前把
这个问题归类为 UI Test Runner 启动环境问题，而不是业务功能断言失败。

## GitHub 状态说明

- `main` 分支代表最新源码。
- Releases 页面代表已打包安装包。
- 当前最新安装包仍为 `v1.1.0`。
- 如果只刷新 Releases 页面，看不到 `main` 的最新源码提交是正常的。
