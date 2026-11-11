# 轻视频 iOS 版（SwiftUI 原生工程）

iOS 原生版，SwiftUI + AVPlayer，无需任何第三方依赖（网络层用系统 `URLSession`）。
功能对齐手机版：首页全屏自动播放信息流、剧场、选集（方块矩阵显示集数）、观看历史、收藏、内置播放器（全屏 / 倍速 / AirPlay 投屏）、内/外网服务器自动检测切换。

> ⚠️ iOS 安装包（.ipa）必须在 **Mac 上使用 Xcode** 打包。本工程已在 Windows 上完整生成，但**无法在本机编译验证**，请在 Mac 上按下面步骤构建。

---

## 目录结构
```
轻视频-ios/
├── project.yml                 # XcodeGen 工程配置（自动生成 .xcodeproj）
├── 轻视频iOS/
│   ├── Info.plist              # 应用配置（含网络权限）
│   ├── App/QingShipinApp.swift # 入口 + 登录态根视图
│   ├── Models/Models.swift     # 数据模型
│   ├── Networking/             # ApiClient(内外网切换)、AuthStore(登录态)
│   └── Views/                  # 登录/主框架/首页/剧场/选集/历史/收藏/播放器
└── README.md
```

## 在 Mac 上构建安装（模拟器）
1. 安装 Xcode（App Store 下载）与 XcodeGen：
   ```bash
   brew install xcodegen
   ```
2. 把 `轻视频-ios` 整个文件夹拷到 Mac。
3. 在 `轻视频-ios` 目录生成工程：
   ```bash
   cd 轻视频-ios
   xcodegen
   open 轻视频iOS.xcodeproj
   ```
4. Xcode 里选择模拟器（如 iPhone 15），点 ▶ 运行，即可在模拟器体验。

## 在真机（iPhone）安装
真机安装需要 Apple 账号签名：
1. Xcode → 打开生成的工程 → 选中 target `轻视频iOS`。
2. `Signing & Capabilities` 里勾选 **Automatically manage signing**，选择你的 Apple ID（免费账号即可）。
3. 把 iPhone 用数据线连上 Mac，Xcode 选择该 iPhone 设备，点 ▶ 运行。
   - 首次需在 iPhone「设置 → 通用 → VPN与设备管理」信任你的开发者证书。
4. 构建产物会直接安装到你手机。

## 关于投屏（AirPlay）
- iOS 上不采用安卓的 DLNA，改用系统自带 **AirPlay**。
- 播放时，播放器底部点 **AirPlay 图标**（带矩形箭头的那个），选择你的电视/音箱即可投屏，本机播放器自动跟随。
- 前提：你的电视需支持 AirPlay（如 Apple TV、支持 AirPlay 的小米/索尼等电视），或通过盒子开启。

## 登录与服务器
- 首次进入自动探测：先试内网 `http://192.168.0.138:8092`，不通则切外网 `http://wym.peterw.top:8092`。
- 账号密码与安卓版相同。

## 常见问题
- **全屏**：播放中点击视频右下角全屏图标，可横屏全屏。
- **自动播放**：首页是上下滑动切换的信息流，当前页自动播放，滑走自动暂停。
- **封面/缩略图**：依赖服务器 `/thumbnails`，需要登录态 token 才能加载。

如需进一步调整（投屏适配、继续播放进度记忆、横屏强制等），告诉我，我把对应源码补进工程再交付。
