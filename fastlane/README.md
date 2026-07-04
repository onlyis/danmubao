fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

①一次性：在 App Store Connect 创建 app 记录

### ios prepare

```sh
[bundle exec] fastlane ios prepare
```

构建前端 H5 产物 + 重新生成 Xcode 工程（打包前置）

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

自动生成各语言截图（snapshot，配置见 Snapfile）

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

②上传商店文案/元数据（不含二进制）

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

上传截图到 App Store Connect（先跑过 screenshots）

### ios build

```sh
[bundle exec] fastlane ios build
```

③打包 IPA（Release / App Store 分发 / 自动签名）

### ios beta

```sh
[bundle exec] fastlane ios beta
```

④打包并上传到 TestFlight（内测）

### ios release

```sh
[bundle exec] fastlane ios release
```

⑤完整发布：构建 + 上传二进制 + 上传元数据（默认不自动提审）

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
