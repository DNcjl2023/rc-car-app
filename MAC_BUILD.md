# Mac 上编译 iOS 包（RC Car App）

本项目是 Flutter 双端应用（Android + iOS）。Android 可直接在 Windows 上用 Android Studio/Flutter 出包；**iOS 必须在 macOS + Xcode 上编译**。本文件是在 Mac 上从零跑起来的步骤。

---

## 1. 一次性环境准备（Mac）

```bash
# 1) 安装 Xcode（App Store 安装），装好后打开一次以接受协议
# 2) 安装 Xcode 命令行工具
xcode-select --install

# 3) 安装 Flutter SDK
#    方式 A：官网 https://flutter.dev 下载，解压后把 bin 加进 PATH
#    方式 B：brew 安装
brew install flutter

# 4) 检查环境
flutter doctor
flutter --version
```

> 如果 `flutter doctor` 提示 Xcode 未配置，运行：
> ```bash
> sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
> flutter doctor
> ```

### 安装 CocoaPods

本项目使用了 `shared_preferences` 等原生插件，需要 CocoaPods：

```bash
sudo gem install cocoapods
# 或
brew install cocoapods
```

---

## 2. 克隆仓库 & 拉取依赖

```bash
git clone https://github.com/DNcjl2023/rc-car-app.git
cd rc-car-app
flutter pub get
cd ios && pod install && cd ..
```

---

## 3. 运行在 Mac 自带的 iOS 模拟器（最省事，无需签名）

```bash
open -a Simulator
flutter devices          # 找到模拟器的 id，形如：iPhone 15 Pro (xxxx)
flutter run -d <模拟器id>
```

模拟器无需 Apple 开发者账号，适合 UI / 功能联调。

---

## 4. 运行/安装到真机 iPhone

```bash
flutter devices          # 找到真机 udid
flutter run -d <真机udid>
```

真机必须签名，步骤：

1. 打开 `ios/Runner.xcworkspace`（不是 Runner.xcodeproj）
2. 给 **Runner** 到 **Signing & Capabilities** 里勾选 **Automatically manage signing**
3. **Team** 选你的 Apple ID（登录一次 Xcode 会把你的 Apple ID 加进来）
4. 若提示换 Bundle ID，把 `com.rcapp.rcCarApp` 改成你唯一的名字（如 `com.你的名字.rcCarApp`）

> 免费 Apple ID 签名：只能装 7 天，且只能装到你自己登录的设备；超过 7 天需重新运行。
> 正式使用 / TestFlight / 上架 App Store：需要 **Apple Developer Program（$99/年）** 账号。

---

## 5. 出正式发布包

```bash
flutter build ios --release
```

产物在 `build/ios/iphoneos/Runner.app`，可再通过 Xcode 的 Archive 上传到 App Store Connect / TestFlight。

---

## 6. 常见问题

| 现象 | 处理 |
| --- | --- |
| `pod install` 失败 | 重跑 `sudo gem install cocoapods`，或 `pod repo update` 后重试 |
| 卡在 `Running pod install` | 关掉 Xcode，`cd ios && pod deintegrate && pod install` |
| 真机连不上 | 确认手机已 `信任` 此电脑，数据线用原装/USB-C |
| 免费账号 7 天过期 | 重新 `flutter run` 或改付费开发者账号 |
| 编译报签名错误 | 确认 Team 已选、Bundle ID 唯一，`flutter clean` 后重跑 |

---

## 7. 项目关键信息

- **Flutter 版本**：3.47.0 / Dart 3.13.0（`flutter --version` 确认）
- **App 版本**：`1.1.0+1`（见 `pubspec.yaml`）
- **Bundle ID**：`com.rcapp.rcCarApp`
- **iOS 最低版本**：15.0
- **依赖**：`cupertino_icons`、`shared_preferences`
