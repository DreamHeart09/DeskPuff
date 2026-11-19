# DeskPuff 构建与打包

本文记录项目如何从源码生成 `dist/DeskPuff.app` 和 DMG，并保留可在其他会话复用的已验证命令与环境记录。打包实现以 `scripts/build-app.sh` 和 `scripts/make-dmg.sh` 为准。

## 环境要求

- macOS 14 或更高版本；当前产物面向 Apple Silicon（arm64）。
- Swift 命令行开发工具，以及与当前 macOS SDK 匹配的 Swift 编译器。
- 要把桌面小组件打包进应用，还需要完整 Xcode 与 XcodeGen。仅使用 Command Line Tools 时，脚本会构建主应用，但不会嵌入 WidgetKit 扩展。
- 以下命令从仓库根目录运行。

如果 SwiftPM 报 Swift 编译器与 SDK 版本不匹配，先选择匹配的 Xcode/Command Line Tools；不要通过改源码或删缓存来绕过工具链不兼容。

## 常用命令

### 重新生成图标资源

`assets/icons/DeskPuff-AppIcon-Art.png` 是应用图标源图，`assets/icons/DeskPuff-MenuBar.svg` 是菜单栏模板源文件。在 macOS 上安装图像依赖并运行下列命令，可生成 1024px AppIcon、菜单栏模板 PNG、ICNS。设计预览输出到本地归档目录，不会纳入 Git：

应用图标 PNG 会保留圆角图形，并将四角相连的深色画布清为透明；ICNS 包含多种 Finder 与 Dock 所需的像素尺寸。当前 Swift Package 工程没有 Xcode Asset Catalog，打包脚本通过 `AppIcon.icns` 提供系统图标，并把 `AppIcon.png` 放入运行时资源包供应用界面复用。

```sh
python3 -m pip install -r scripts/requirements-icons.txt
python3 scripts/generate-icons.py
```

生成后按上面的 `build-app.sh` 命令重新构建应用。

### 构建本地 Debug 应用

最简单的方式是在项目根目录运行：

```sh
make debug
open dist/DeskPuff.app
```

需要指定独立缓存目录时，可使用下面的等效构建命令：

```sh
cd "$(git rev-parse --show-toplevel)"
mkdir -p /private/tmp/deskpuff-build/module-cache /private/tmp/deskpuff-build/swift-module-cache
CLANG_MODULE_CACHE_PATH=/private/tmp/deskpuff-build/module-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/deskpuff-build/swift-module-cache \
DESKPUFF_SCRATCH_DIR=/private/tmp/deskpuff-build \
DESKPUFF_DISABLE_SWIFT_SANDBOX=1 \
DESKPUFF_CONFIGURATION=debug \
./scripts/build-app.sh
codesign --verify --deep --strict dist/DeskPuff.app
```

变量说明：

- `DESKPUFF_CONFIGURATION`：SwiftPM 配置，支持 `debug` 或 `release`；未设置时为 `release`。
- `DESKPUFF_SCRATCH_DIR`：SwiftPM scratch/build 目录；上例把产物放到 `/private/tmp/deskpuff-build`。
- `CLANG_MODULE_CACHE_PATH`、`SWIFT_MODULECACHE_PATH`：将 Clang 与 Swift 模块缓存放进可写临时目录。
- `DESKPUFF_DISABLE_SWIFT_SANDBOX=1`：让构建脚本给 `swift build` 加上 `--disable-sandbox`。本执行环境不加该项会在 SwiftPM manifest 阶段报 `sandbox_apply: Operation not permitted`。
- `DESKPUFF_CONFIGURATION=debug`：生成便于本机调试的 Debug app；这是当前 Command Line Tools 环境中已成功验证的配置。

`build-app.sh` 会先执行 `swift build -c <配置>`，再通过 `swift build ... --show-bin-path` 查找产物目录。第二次调用一般只查询路径并复用刚构建的结果。随后脚本会删除并重建 `dist/DeskPuff.app`：复制 `DeskPuff` 可执行文件和 `DeskPuff_DeskPuff.bundle` 资源，写入最低系统 `14.0` 的 `Info.plist`，最后执行 ad-hoc 本地签名。`DESKPUFF_VERSION` 和 `DESKPUFF_BUILD_NUMBER` 可设置版本号与构建号；默认值分别为 `0.1.0` 和 `1`。DMG 命令会自动将两者设成同一个版本号。

如果同时检测到可用的完整 Xcode 和 `xcodegen`，脚本还会根据 `WidgetExtension/project.yml` 生成 Xcode 工程，构建 `DeskPuffWidgetExtension.appex`，将小组件嵌入 `Contents/PlugIns`，再按 App Group 权限为扩展和主应用签名。构建日志会打印 `Built dist/DeskPuff.app`；若小组件工具链缺失，则会提示 `Widget extension sources are ready; install full Xcode to build and embed the desktop widget.`。后者表示主应用已生成，但桌面组件不会出现在该应用包中。

若要尝试 Release 构建，可省略 `DESKPUFF_CONFIGURATION=debug` 或显式设为 `release`。当前部分 Command Line Tools 环境会在编译成功后调用 `dsymutil` 生成 dSYM 时返回 `Operation not permitted`，此时脚本不会完成 app 替换；先用上面的 Debug 命令构建本地验证版。`make-dmg.sh` 仍使用默认 Release 配置，因此若 Release 的 dSYM 阶段失败，DMG 也无法生成。发布前应在匹配且完整的 Xcode/Command Line Tools 环境重试 Release 与 DMG。

**注意：** 运行脚本会替换已有的 `dist/DeskPuff.app`。`dist/` 与 `.build/` 均被 `.gitignore` 忽略，不属于源码提交内容。

### 制作社区 Release DMG

```sh
make dmg 0.1.1
```

脚本会重新构建 Release app（不复用 Debug 包），验证应用结构、Info.plist 与代码签名，在 DMG 中放入 `.app`、`/Applications` 快捷方式、许可证和双语安装说明，然后生成压缩只读镜像 `dist/DeskPuff-<版本>-arm64.dmg`、运行 `hdiutil verify` 并写出相邻的 `.sha256` 文件。需要 macOS、完整 Xcode 和 `xcodegen`，以便把 WidgetKit 扩展一起构建进包。

脚本会先询问是否已确认随包素材的公开分发权。请检查图片、字体、品牌/商标和第三方素材；未确认前选择 `N` 取消打包。

DMG 使用 ad-hoc 签名且未经 Apple 公证，首次启动可能显示 Gatekeeper 提示。用户应先从官方 Release 获取文件并核对 SHA-256；如确认来源可信，可在 Finder 中按住 Control 单击应用并选“打开”，或按 macOS 提示到“系统设置 → 隐私与安全性”确认。不要要求用户全局关闭 Gatekeeper。若今后具备条件，Developer ID 签名与 Apple 公证是更顺畅的外部分发方式。

上传 GitHub Release 时，应同时上传 `.dmg` 和 `.dmg.sha256`，在发布说明中注明 Apple Silicon、macOS 最低版本、ad-hoc/未公证状态和素材授权核查情况，并提供与该二进制对应的源码和构建标签。下载后可运行：

```sh
shasum -a 256 -c DeskPuff-0.1.1-arm64.dmg.sha256
hdiutil verify DeskPuff-0.1.1-arm64.dmg
```

SHA-256 可发现传输损坏，但若校验和与 DMG 来自同一位置，并不能单独证明发布者身份。正式发布仍须完成本页后续的源码、授权、签名和分发检查。

## 构建后验证和手动验收

确认应用包包含主程序、资源、正确的 plist，并且 ad-hoc 签名可验证：

```sh
test -x dist/DeskPuff.app/Contents/MacOS/DeskPuff
test -d dist/DeskPuff.app/Contents/Resources/DeskPuff_DeskPuff.bundle
plutil -lint dist/DeskPuff.app/Contents/Info.plist
codesign --verify --deep --strict dist/DeskPuff.app
```

若 DeskPuff 已在运行，先从菜单栏选择“退出”，再启动刚生成的包，避免误测到旧进程：

```sh
open dist/DeskPuff.app
```

手动检查撞击形变时，将烟头缓慢正面压向屏幕边缘，再较快斜向撞击数次：每次碰撞会在受力点和抓取点之间形成一到两处局部折痕；不同位置的碰撞应累积新折痕，同一位置则加深已有折痕。折痕随对应部位燃尽消失。程序坞不参与香烟的碰撞掐灭；烟灰落到程序坞的碰撞由独立逻辑处理并应继续保留。高光与两侧阴影应跟随弯折后的烟身走向。此手动检查不能由单纯的源码构建或 `swift test` 替代。

## 已验证记录

- 2026-11-10：本地 Debug 命令（临时模块缓存、`DESKPUFF_DISABLE_SWIFT_SANDBOX=1`）成功构建并签署 `dist/DeskPuff.app`；`codesign --verify --deep --strict` 通过。SwiftPM 仍报告用户级缓存只读以及 Command Line Tools 中缺失 framework/search path 的 warning，但不影响 Debug app 生成。
- 同日 Release 构建通过 Swift 编译阶段，但 `dsymutil` 在 `GenerateDSYMFile` 阶段返回 `Operation not permitted`；因此没有生成 Release app/DMG。更换缓存目录不能解决该 dSYM 权限错误。
- 同次尝试中 `codesign --verify --deep --strict dist/DeskPuff.app` 通过。`open dist/DeskPuff.app` 在该 Codex 桌面执行环境返回 `kLSNoExecutableErr`；直接启动可执行文件也在 AppKit 注册应用阶段中止。因此当时确认了打包产物和签名，没有确认该执行环境中的实际启动或动画观感。该限制可能依赖桌面/Launch Services 环境；在真实 macOS 桌面会话中仍应按上节重新启动并手动验收。
- 如果构建失败，记录完整命令、`swift --version`、`xcrun --sdk macosx --show-sdk-version` 和首次错误。不要把 SwiftPM 编译缓存中残留的旧可执行文件当作本次构建成功的证据。

## 签名与分发边界

社区 DMG 使用 ad-hoc 签名，未经公证，因此首次启动可能显示 Gatekeeper 提示。Release 页面应如实标注签名状态；Developer ID 签名与公证可改善正式分发体验。

## GitHub Releases 授权检查

当前 [CI](../.github/workflows/build.yml) 只运行测试和 App 构建，仓库中没有自动发布任务。`Package.swift` 会复制运行时资源目录，`build-app.sh` 会把资源 bundle 和应用图标整包带入 App，`make-dmg.sh` 再把 App 放进 DMG。脚本要求维护者显式确认素材授权，但该确认不会替代实际核查。本地现有包包含品牌烟盒和实拍火焰图集；相关再分发权清点通过前，仅作为内部构建使用。

### 检查源码、成品与媒体

1. 先依据[素材授权](../ASSET_LICENSE.md)逐项确认拟公开文件。检查公开 Git 历史与标签、实际源码归档、最终 App 及内嵌组件、DMG 和宣传素材。未经确认的贴图、品牌衍生素材和图集应先取得所需授权或从公开发行范围排除，再从批准的源码构建。单独检查 fallback 样式、品牌文案及相关功能，确认公开包可正常构建和运行。
2. 每次发行从确定的提交构建，记录提交 SHA、标签和构建方式。把完整 [GPL v3 文本](../LICENSE)、适用的版权和许可声明，以及[素材与许可说明](../ASSET_LICENSE.md)随安装包提供。可在签名前放入 App 的 `Contents/Resources`，并在 DMG 根目录提供一份便于查阅的副本。最终成品应保留随包素材实际适用的署名和条款。按实际界面核对 GPL 第 5 节关于保留适当交互式法律声明的适用性。
3. 在同一 GitHub Release 的二进制下载旁明确提供**对应源码**的获取方式，按 GPL 第 6(d) 节提供等价且无需额外付费的访问，并持续保证可获取。源码必须能对应实际发行的二进制，包括程序的首选修改形式、构建和安装所需的脚本及配置、所发行的组件与适用声明，系统库和规定豁免的工具除外。仓库标签自动生成的 ZIP/TAR 只有在内容确实充分、与二进制一致时才可使用。否则另附经过核对的源码归档。[GNU GPL v3 第 1、6 节](../LICENSE) · [GitHub Releases 说明](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
4. 发布前用干净环境下载同一组安装包和源码，核对包内通知、实际资源清单与构建文档。依据具体分发情形核对 GPL 第 6 节的 Installation Information 要求。正式 macOS 分发还需单独验证签名、公证和下载后的运行。若采用限制再分发或对修改版施加额外条件的商店、DRM 或 EULA，先核对能否同时满足 GPL 第 3、6、10 节与渠道条款。

### 支持者版本与独立内容包

官方可以销售 GPL 版本、提供支持者服务，也可以对拥有充分权利的独立内容采用独立商业许可。免费基础版继续按 GPL 维护。对咖啡、饮料、零食或外卖扩展，优先评估独立发布的图片、音频和数据包。现有[样式包](style-packs/README.md)采用 JSON 与图片，可作为内容格式的参考。评估数据是否独立创作、是否实际独立于程序、是否为构建或运行 GPL 作品所必需，以及打包方式和许可会不会限制接收方行使 GPL 权利。

若扩展加入 Swift 或 Metal 代码、链接核心库、调用内部接口、共用复杂程序状态，或与主程序共同构成单一作品，需在实现和销售前再审查。分开下载、用进程通信或改名为 DLC，均不能单独决定授权边界。若构成 GPL 覆盖的组合，分发须遵守 GPL，包括相应源码义务。权利完整的程序代码可以另行评估双重授权。第三方贡献仍归各自权利人，超出既有许可的重授权需要取得授权。[GNU GPL v3 第 5、6 节](../LICENSE) · [FSF 对聚合和插件的说明](https://www.gnu.org/licenses/gpl-faq.html#GPLPlugins)
