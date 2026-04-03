# FlyHero (飞行侠)

一款 macOS 菜单栏工具，自动监听剪贴板中的飞书链接，通过 Claude Code 调用 lark-cli 将飞书文档下载到本地指定目录。

## 工作原理

```
用户复制飞书链接
    |
    v
ClipboardMonitor (每 1.5 秒轮询剪贴板)
    |
    v
FeishuLinkParser (识别链接类型: 文档/表格/多维表格/云空间/知识库/妙记)
    |
    v
DownloadTaskManager (创建任务, 等待用户确认)
    |
    v
用户点击确认
    |
    v
ClaudeCodeRunner (启动 claude --print 进程, 构造 lark-cli 下载指令)
    |
    v
claude CLI -> lark-cli -> 飞书 API -> 文件下载到目标目录
    |
    v
DownloadHistoryManager (记录下载历史, 持久化到本地 JSON)
```

核心思路: 应用本身不直接调用飞书 API, 而是通过 `claude --print` 启动一个 Claude Code 进程, 让 AI 根据链接类型自动选择 `lark-cli` 的合适命令来完成下载。这样可以利用 Claude 的智能判断来处理各种飞书链接格式和边界情况。

## 下载格式

| 飞书内容类型 | URL 特征 | 下载格式 |
|-------------|---------|---------|
| 文档 | `/docs/` `/docx/` | PDF |
| 电子表格 | `/sheets/` | XLSX |
| 多维表格 | `/base/` | XLSX |
| 云空间文件 | `/file/` `/drive/` | 原始格式 |
| 知识库 | `/wiki/` | PDF / XLSX (自动判断) |
| 妙记 | `/minutes/` | TXT |

所有下载的文件会使用飞书中的原始标题作为文件名。

## 项目架构

```
FlyHero/
├── App/                          # 应用入口与生命周期
│   ├── FlyHeroApp.swift          # @main SwiftUI App
│   └── AppDelegate.swift         # 生命周期管理, 菜单栏图标, 剪贴板监控启动
│
├── FloatingIsland/               # 悬浮窗 (单 NSPanel 架构)
│   ├── FloatingPanelController.swift  # NSPanel 生命周期与尺寸管理
│   ├── IslandContentView.swift        # SwiftUI 胶囊视图 + 内嵌任务列表
│   ├── TaskListPanel.swift            # TaskRowView 任务行组件
│   └── VisualEffectView.swift         # 毛玻璃效果包装
│
├── MainWindow/                   # 主窗口 (设置 + 历史)
│   ├── MainWindowController.swift     # NSWindow 管理, 全屏支持
│   └── MainWindowView.swift           # Tab 切换视图 (设置/历史)
│
├── MenuBar/                      # 菜单栏弹出面板
│   └── SettingsView.swift             # 目录选择, 悬浮窗开关, 退出
│
├── Plugins/                      # 剪贴板监控
│   └── ClipboardMonitor.swift         # NSPasteboard 轮询, 飞书 URL 检测
│
├── Services/                     # 核心服务层
│   ├── ClaudeCodeRunner.swift         # claude --print 进程管理与 Prompt 构造
│   ├── Constants.swift                # 应用常量 (尺寸, 颜色, Key)
│   ├── DownloadHistory.swift          # 下载历史持久化 (JSON, 最近100条)
│   ├── DownloadTaskManager.swift      # 任务队列 (串行执行, 去重, 确认/重试)
│   ├── FeishuLinkParser.swift         # 飞书 URL 解析 (类型识别 + Token 提取)
│   ├── LaunchAtLoginService.swift     # 开机启动 (SMAppService)
│   └── SettingsManager.swift          # 设置持久化 (安全书签 + UserDefaults)
│
├── Assets.xcassets/              # 资源文件
│   ├── AppIcon.appiconset/            # 应用图标
│   ├── MenuBarIcon.imageset/          # 菜单栏图标
│   └── TransferIcon.imageset/         # 悬浮窗骑手图标
│
├── Info.plist                    # 应用配置
└── FlyHero.entitlements          # 沙盒权限
```

### 关键设计决策

- **单 NSPanel 悬浮窗**: 胶囊和任务列表合并为同一个 NSPanel, 展开/收起通过 SwiftUI 动画 + Panel 尺寸调整实现, 避免多窗口同步导致的卡顿
- **NSPanel + nonactivatingPanel**: 悬浮窗不会抢夺焦点, 不影响用户当前操作
- **安全书签 (Security-Scoped Bookmark)**: macOS 沙盒下持久化用户选择的目录权限
- **串行任务队列**: 一次只运行一个 claude 进程, 避免资源竞争
- **用户确认机制**: 检测到链接后不自动下载, 需用户点击确认
- **深浅色主题适配**: 使用系统语义色, 自动跟随 macOS 外观设置

## 使用条件

### 系统要求

- macOS 13 (Ventura) 或更高版本
- Apple Silicon 或 Intel Mac

### 前置依赖

1. **Claude Code CLI** - 必须已安装并登录

   ```bash
   # 安装
   npm install -g @anthropic-ai/claude-code
   
   # 登录
   claude
   ```

2. **lark-cli** - 必须已安装并完成飞书授权

   ```bash
   # 安装
   npm install -g lark-cli
   
   # 登录飞书
   lark-cli auth login
   ```

3. **lark-cli Skills** (推荐安装, Claude 使用 lark-cli 时更准确)

   ```bash
   npx skills add larksuite/cli --all -y
   ```

### 验证环境

```bash
# 确认 claude 可用
which claude

# 确认 lark-cli 可用
which lark-cli

# 确认飞书已登录
lark-cli contact +search-user --query "你的名字"
```

## 编译与运行

### 编译

```bash
# Debug 编译
swift build

# Release 编译
swift build -c release
```

### 打包为 .app

```bash
# 编译 Release
swift build -c release

# 创建 .app 结构
APP_DIR="build/FlyHero.app"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp .build/release/FlyHero "${APP_DIR}/Contents/MacOS/FlyHero"
cp FlyHero/Info.plist "${APP_DIR}/Contents/"

# 编译 Asset Catalog (图标等)
actool --compile /tmp/flyhero_assets \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /tmp/flyhero_assets/AssetInfo.plist \
  FlyHero/Assets.xcassets

cp /tmp/flyhero_assets/Assets.car "${APP_DIR}/Contents/Resources/"
cp /tmp/flyhero_assets/AppIcon.icns "${APP_DIR}/Contents/Resources/"
mkdir -p "${APP_DIR}/Contents/Resources/FlyHero_FlyHero.bundle"
cp /tmp/flyhero_assets/Assets.car "${APP_DIR}/Contents/Resources/FlyHero_FlyHero.bundle/"

# 启动
open "${APP_DIR}"
```

## 操作说明

### 首次使用

1. 启动应用后, 屏幕上会出现一个胶囊形悬浮窗, 菜单栏出现摩托车图标
2. 点击悬浮窗 → 弹出 "点击设置同步目录" → 选择文件保存目录
3. 设置完成后, 应用开始监听剪贴板

### 下载文件

1. 在浏览器或飞书中**复制**一个飞书文档链接
2. 悬浮窗变为橙色, 显示 "确认 1", 自动展开任务列表
3. 点击任务右侧的 **绿色勾** 确认下载, 或 **红色叉** 取消
4. 确认后任务进入队列, 悬浮窗显示 "配送中..."
5. 下载完成后文件保存到设置的同步目录

### 悬浮窗操作

- **鼠标悬停**: 胶囊展开, 显示当前状态
- **点击**: 展开/收起任务列表
- **拖动**: 可自由拖动到屏幕任意位置
- **鼠标移出**: 自动收起

### 菜单栏操作

- **点击摩托车图标**: 弹出控制面板
  - 选择/更改同步目录
  - 显示/隐藏悬浮窗
  - 退出应用

### 主窗口

- **打开方式**: 点击 Dock 图标
- **设置 Tab**: 查看/更改同步目录, 查看运行状态
- **历史 Tab**: 查看最近 100 条下载记录, 点击箭头按钮在 Finder 中定位文件

### 任务状态

| 状态 | 说明 |
|------|------|
| 待确认 (橙色) | 检测到飞书链接, 等待用户确认 |
| 等待中 (灰色) | 已确认, 排队等待执行 |
| 配送中 (蓝色) | 正在通过 Claude + lark-cli 下载 |
| 完成 (绿色) | 下载成功 |
| 失败 (红色) | 下载失败, 可点击重试 |

## 支持的飞书域名

- `*.feishu.cn`
- `*.larksuite.com`
- `*.feishu.net`

## 数据存储

| 数据 | 位置 |
|------|------|
| 下载历史 | `~/Library/Application Support/FlyHero/download_history.json` |
| 同步目录设置 | UserDefaults (安全书签) |
| 窗口位置 | UserDefaults |

## 技术栈

- Swift 5.9 / Swift Package Manager
- SwiftUI + AppKit (NSPanel, NSWindow, NSStatusItem)
- macOS 13+ (Ventura)
- 零第三方依赖

## License

MIT
