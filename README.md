# LX 音乐 — iOS 客户端

为 [lxserver](https://github.com/XCQ0607/lxserver)（LX Music Sync Server 增强版）打造的 **原生 iOS 客户端**。

界面简洁、操作参考**汽水音乐**：底部三 Tab（推荐 / 歌单 / 我的）+ 全屏播放页 + 迷你播放条 + 搜索。完整覆盖 lxserver **Web 播放器全部用户功能**。

---

## 功能总览（对应 lxserver web 端）

| 分类 | 功能 | 状态 |
| --- | --- | --- |
| 连接 | 服务器地址 / 播放器访问密码 / 用户账号登录（x-user-token） | ✅ |
| 发现 | 多源聚合搜索（QQ/网易/酷狗/酷我/咪咕）+ 联想提示 + 热门搜索 | ✅ |
| 歌单 | 歌单广场（分类标签）、歌单详情、多平台排行榜 | ✅ |
| 播放 | 全屏播放页（模糊封面背景）、滚动同步歌词、倍速、进度拖动、音量 | ✅ |
| 队列 | 播放队列、切换、拖拽排序、顺序播放 | ✅ |
| 音质 | 标准 128K / 高品质 320K / 无损 / Hi-Res / 母带 | ✅ |
| 我的 | 同步歌单与收藏（用户列表）、增删歌曲、缓存管理、快照备份 | ✅ |
| 下载 | 服务器代理下载（自动注入 ID3 标签） | ✅ |
| 评论 | 歌曲评论（hot/new） | ✅ |
| 设置 | 默认音质、深色模式、服务器信息 | ✅ |

> 说明：lxserver 的“管理后台（/admin）”属于服务器运维范畴，未纳入客户端；其余 Web 播放器用户侧功能均已覆盖。

---

## 快速获得 .ipa（推荐方式：GitHub Actions 自动构建）

本项目内置了自动构建流水线，**无需 Mac 即可产出 .ipa**：

1. 把本仓库推送到你自己的 GitHub 账号（或直接新建仓库上传本项目）。
2. GitHub Actions 会在 macOS runner 上自动编译并打包，push 到 `main` 即触发。
3. 到仓库 **Actions** 页面，找到最新一次 `Build iOS IPA`，在底部 **Artifacts** 下载 `LXMusicClient.ipa`。
4. 也可在 **Actions → Build iOS IPA → Run workflow** 手动触发，触发时会额外生成一个 GitHub **Release** 备用。

> 默认产出为**未签名** .ipa，可用 **TrollStore（巨魔）** 直接安装。
> 如需签名（AltStore/Sideloadly 等），在仓库 Secrets 配置证书后取消流水线中签名步骤注释即可。

---

## 在 iPhone 上安装

- **TrollStore（巨魔）**：下载 .ipa，用 TrollStore 打开/导入即可安装，无需签名。
- **AltStore / Sideloadly**：需要 Apple ID 免费签名（需配置签名后重新构建，或在本地 Mac 用 Sideloadly 直接签 `.app`/`.ipa`）。

---

## 连接你的 lxserver

首次启动填写：

- **服务器地址**：`http://<你的服务器IP>:9527`（默认端口 9527）
- **播放器访问密码**：仅当服务器开启了 Web 播放器密码认证（`ENABLE_WEBPLAYER_AUTH=true`）时填写。
- **用户账号（可选）**：勾选后填写后台“用户管理”中的用户名/密码，可同步歌单、收藏、缓存。

> 服务器侧常用环境变量（Docker）：
> ```yaml
> - ENABLE_WEBPLAYER_AUTH=true
> - WEBPLAYER_PASSWORD=你的密码
> ```

---

## 本地开发（需要一台 Mac + Xcode）

环境要求：macOS + Xcode 15+，iOS 16+。

```bash
# 1) 用 XcodeGen 生成工程（可选；仓库已自带 .xcodeproj，可直接打开）
brew install xcodegen
xcodegen generate

# 2) 打开工程运行
open LXMusicClient.xcodeproj
```

- 部署目标：iOS 16.0
- Bundle ID：`com.lxmusic.client`
- 已在 Info.plist 中开启 ATS 任意加载（允许局域网 http）与后台音频。

---

## 工程结构

```
LXMusicClient-iOS/
├── LXMusicClient.xcodeproj/       # 已生成的 Xcode 工程
├── project.yml                    # XcodeGen 定义（工程生成的单一来源）
├── .github/workflows/build-ipa.yml# 自动构建 .ipa 流水线
└── LXMusicClient/
    ├── LXMusicClientApp.swift     # 入口
    ├── Models/                    # 数据模型（容错解析多平台返回）
    ├── Networking/                # ServerConfig + LXAPIClient（全部 REST API）
    ├── Player/                    # PlayerManager（AVPlayer）+ 歌词解析
    ├── Stores/                    # AppSession（连接/登录/外观）
    ├── Views/                     # 全部界面（参考汽水音乐）
    └── Assets.xcassets / Info.plist
```

---

## 许可

本客户端仅供个人学习使用。请遵守 lxserver 与其所聚合音源平台的版权与使用条款，勿用于商业用途。
