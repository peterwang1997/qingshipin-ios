# 轻视频 iOS 客户端

连接飞牛 NAS 上部署的 **轻视频（LiteVideo）** 后端的原生 iOS 客户端，功能与安卓端一一对应。

- 原生 SwiftUI 开发，**非 WebView 套壳**
- 内置 AVPlayer 播放，支持全屏、左右拖拽进度、长按 2x 加速
- 内置 UPnP/DLNA 控制点，可搜索并投屏到智能电视
- 界面尺寸按 iPhone 15 Pro Max（430×932pt）适配，同时兼容其他全面屏机型

## 功能清单

| 模块 | 说明 |
|------|------|
| 登录 | 服务器地址 + 用户名 + 密码，JWT 鉴权，支持一键探测内外网 |
| 内外网切换 | 启动自动探测内网/外网服务器地址，登录页与「我的」页均可手动修改 |
| 首页 | **全屏自动播放信息流**：随机推荐、1 页 1 视频、上下滑动换视频 |
| 剧场 | 短剧库两列网格；**点封面直接续播**（自动加载上次播放集数，无历史播第 1 集） |
| 多季折叠 | 同一部剧的多季按季号归并，点开进入选季页，各季显示观看进度 |
| 播放器 | 内置播放，全屏横屏；**上下滑动换集、长按 2x 加速、双击播放/暂停、单击切换顶栏** |
| 投屏 | SSDP 搜索 MediaRenderer，SetAVTransportURI + Play 投屏，换集自动同步、播完自动连播下一集 |
| 观看进度 | 每 10 秒上报进度；进入播放器时从服务端续播（>8 秒且 <97% 才跳） |
| 收藏 | 收藏列表（`feed?type=favorites`） |
| 观看历史 | `feed/watched`，含接口异常容错 |
| 管理后台 | 媒体库路径管理（扫描/停止/删除/添加）、用户管理（重置密码/删除） |
| 我的 | 用户信息、观看历史、服务器切换、管理后台、退出登录 |

## 后端接口

- 登录：`POST /api/auth/login` → JWT，请求头 `Authorization: Bearer <token>`
- 信息流：`GET /api/feed?type=video|favorites|music`
- 剧集：`GET /api/series`、`GET /api/series/{id}/episodes`
- 历史：`GET /api/feed/watched`、`GET /api/history/series/{id}`
- 播放流：`GET /stream/{id}?token=<jwt>&codec_*`（MP4，支持 HTTP Range）
- 缩略图：`GET /thumbnails/{name}?token=<jwt>`
- 进度：`POST /api/video/{id}/progress`
- 管理：`GET/POST/DELETE /api/admin/paths`、`/api/admin/paths/{id}/scan`、`/api/admin/users`

## 目录结构

```
Sources/
├── App/          应用入口、全局状态、方向控制
├── Core/         播放器封装、季号解析、本地存储与 Toast
├── Models/       数据模型（字段与后端逐项对应）
├── Networking/   ApiClient / ApiService / DlnaManager
├── UI/           主题配色与通用组件
└── Views/        启动、登录、首页、剧场、收藏、历史、我的、播放器、管理后台
Resources/         Info.plist、Assets.xcassets、AppIcon
project.yml        XcodeGen 工程描述
codemagic.yaml     Codemagic 未签名打包流程
```

## 构建

工程用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 描述，避免把 `.xcodeproj` 放进仓库产生冲突：

```bash
brew install xcodegen
xcodegen generate
open Qingshipin.xcodeproj
```

命令行编译未签名 ipa（Codemagic / CI 同款）：

```bash
xcodebuild -project Qingshipin.xcodeproj -scheme Qingshipin \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS=""
```

## 使用说明

1. 首次打开自动探测服务器：内网 `http://192.168.0.138:8092`，外网 `http://peterw.top:8092`，也可手动填写
2. 使用服务器已有账号登录
3. **首页**：全屏视频流自动播放，上下滑动切换，右侧按钮可换一批 / 进入播放器
4. **剧场**：点封面直接进入播放器并续播上次那一集；多季剧点开进入选季
5. **播放器**：上下滑动换集、左右拖动进度、长按 2x、双击暂停、单击呼出顶栏；右上角投屏与全屏
6. **投屏**：点投屏图标 → 选择电视 → 推送播放；换集自动同步

> 说明：iOS 的 DLNA 组播在部分路由器开启 AP 隔离时会搜不到设备，此时请确认手机与电视在同一网段。
