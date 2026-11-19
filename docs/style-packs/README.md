# DeskPuff 外部样式包

第三方开发者和普通用户可以通过文件夹添加香烟、烟盒、烟灰缸或打火机样式，不需要编写 Swift、脚本或插件代码。应用只读取 `manifest.json` 和 PNG 图片，不会运行样式包中的程序。香烟包定义烟纸、滤嘴颜色/贴图、直径与烟雾量和颜色；打火机包定义外壳贴图、材质和火焰色阶；燃烧、点火、烟灰、拖拽、碰撞等仍复用应用内的统一物理逻辑。

## 安装位置

在 DeskPuff 菜单栏菜单中点击 **打开样式文件夹…**，应用会在 Finder 打开样式根目录。也可以在 Finder 按 `Shift-Command-G` 并输入：

```text
~/Library/Application Support/DeskPuff/Styles/
```

内置和社区烟盒都使用同一套 v1 文件格式；资源包放在仓库 `Sources/DeskPuff/Resources/StylePackages/`，社区样式安装到用户目录后无需改 Swift 代码。

香烟包放在 `cigarettes`，烟盒包放在 `cigarette-boxes`，烟灰缸包放在 `ashtrays`，打火机包放在 `lighters`。每个包单独放入一个目录，目录名必须与 manifest 的 `id` 相同：

```text
Styles/
├── cigarettes/
│   └── sample-community-slim/
│       ├── manifest.json
│       ├── preview.png
│       └── artwork/
│           ├── paper.png
│           └── filter.png
├── cigarette-boxes/
│   └── sample-cloud-red/
│       ├── manifest.json
│       └── artwork/
│           ├── body.png
│           └── lid-outside.png
├── ashtrays/
    └── sample-celadon/
        ├── manifest.json
        ├── preview.png
        └── artwork/
            └── ashtray.png
└── lighters/
    └── sample-lighter/
        └── manifest.json
```

在控制面板中导入完整样式包文件夹，或复制到相应类别目录后点击重新扫描。面板可以设置香烟与烟盒套装、独立管理烟灰缸和打火机样式，也可以编辑烟支参数。烟盒包 manifest 中的 `cigaretteStyleId` 是包的默认关联；面板保存的用户关联优先于包内值。

香烟的纸张、滤嘴、直径和烟雾倍率可在面板直接修改。内置样式需先“复制后编辑”，社区样式可直接保存。改色、尺寸、烟量支持不依赖图片的参数化样式；纸张/滤嘴 PNG 是可选的细节叠层，`preview.png` 用于列表预览。默认烟支样式与参数保存在用户偏好中，样式包保存在 `~/Library/Application Support/DeskPuff/Styles/cigarettes/`。

打火机包只调整外观，不改变点火物理：`palette.body` 是外壳渐变，`palette.rim` 是金属渐变，`palette.flame` 是火焰色阶；也可提供完整的透明 `artwork.whole` PNG。操作方式为右键开盖并点火、再次右键熄火合盖；左键拖动移动，拖动角落旋转。样式目录是 `~/Library/Application Support/DeskPuff/Styles/lighters/<id>/`，内置基底为 `silver-flint`、`warm-brass` 和 `midnight-enamel`。

## 准备素材

所有素材使用 PNG，透明背景推荐使用 RGBA。图片最多 4096 × 4096 像素、单张不超过 16 MB；单个样式包总图片不超过 64 MB，全部外部样式不超过 256 MB。实际制作建议按目标显示尺寸的 2× 或 3× 导出。

### 烟盒包

从 [两张贴图的烟盒样例](examples/sample-cloud-red/) 复制整个文件夹，改掉目录名和 manifest 的 `id`，然后替换两张 RGBA PNG。

| 字段 | 建议尺寸 | 画面与对齐 |
| --- | --- | --- |
| `artwork.body` | 440 × 688 | 对齐整盒正面比例；顶部活动盒盖覆盖的区域保持透明，下面只画盒身印刷。默认模板盖带占高度 `25/86`；自定义比例由 `geometry.lidBandFraction` 指定。 |
| `artwork.lidOutside` | 440 × 200 | 默认盖带与身图同宽，画活动盒盖外侧印刷。盖顶和盖底对齐闭合面。若改用非默认盖缝，按盒身正面比例和盖带高度同步调整贴图高宽比。 |

可同比例提高像素尺寸。两张图里只画外侧印刷；程序不再叠加额外的盒身彩色边框。厚度、接缝、内部纸板、盒盖内面和开合光影由 DeskPuff 绘制，盒口薄纸与锡箔区域使用全款共用的中华实拍内衬素材。预览图可通过 `preview` 选填。随包提供 `body` 和 `lidOutside` 两张图即可复用一致的开盒结构。

`geometry` 可选地描述盒型，不再依赖单个品牌 ID。`type` 支持 `standard-hard` 和 `slim-hard`；`frontAspectRatio` 是正面宽高比，`lidBandFraction` 是从盒顶到盖缝的高度比例，`rowCounts` 描述每排烟支数，`cigaretteCount` 是总支数，`cigaretteDiameterMM` 可指定支径。细支两排样式可用 `[10, 10]`、约 `5.4` mm 支径和对应正面比例配置。若真实烟盒使用不同于翻盖的结构，先按同型号开盒实拍确认，再扩展结构类型；只更换两张外观图不能模拟侧拉或滑盖机构。

旧包仍可使用 `front`（整张关闭正面，上方约 `25/86` 映射到盒盖）、`scaledBody`（缩放取放模式）和 `lidOutsideOpen`（盒盖外侧备用图）。配色包仍可只提供 `palette`。旧 `lidInside` 路径和 `palette.lidInterior`、`palette.mouthEdge` 会被忽略，原内盖 PNG 可以删除。只有 `lidInside` 的旧包会显示基底的外观。

### 烟灰缸包

- `artwork/ashtray.png`：可选的完整烟灰缸主体贴图，透明背景，覆盖碟身、碟沿和碟内材质；存放的烟灰由应用绘制，旋转通过拖动外缘触发，不需要在贴图中绘制旋转按钮。
- 不提供完整贴图时，可通过 `palette` 更换主体、碟沿、内盆、釉面高光和把手颜色。
- `geometry.basin` 可选，用来让烟灰落在内盆中。它是 `[x, y, width, height]` 四个 0 到 1 的归一化数值，坐标基于未旋转的 320 × 210 设计画布，原点在左下角。内盆碰撞和存灰区域目前按椭圆处理。

## Manifest 字段

完整字段约束见 [schema.json](schema.json)，可在支持 JSON Schema 的编辑器中获得自动补全和格式校验。仓库提供可复制的样例：

- [烟盒样例](examples/sample-cloud-red/manifest.json)
- [烟灰缸样例](examples/sample-celadon/manifest.json)
- [香烟样例](examples/sample-community-slim/manifest.json)
- [打火机样例](examples/sample-lighter/manifest.json)

最小烟盒 manifest：

```json
{
  "schemaVersion": 1,
  "type": "cigaretteBox",
  "id": "my-pack",
  "name": "我的烟盒",
  "author": "作者名",
  "license": "CC BY 4.0",
  "paletteBase": "yunlan-red",
  "artwork": {
    "body": "artwork/body.png",
    "lidOutside": "artwork/lid-outside.png"
  }
}
```

最小烟灰缸 manifest：

```json
{
  "schemaVersion": 1,
  "type": "ashtray",
  "id": "my-ashtray",
  "name": "我的烟灰缸",
  "author": "作者名",
  "license": "CC BY 4.0",
  "paletteBase": "porcelain",
  "artwork": {
    "whole": "artwork/ashtray.png"
  },
  "geometry": {
    "basin": [0.091, 0.252, 0.819, 0.371]
  }
}
```

`paletteBase` 可省略。烟盒默认基底为 `zhonghua-fallback`；旧版 `yunlan-red`、`jade-green`、`midnight-blue` 仅为兼容旧包保留颜色解析，不会出现在可选预设中。烟灰缸当前内置基底为 `clear-glass`。样式可以覆盖对应类型支持的外观颜色。颜色写作 `#RRGGBB` 或 `#RRGGBBAA`，渐变写作 2 到 4 个颜色组成的数组。

打火机样式放在 `~/Library/Application Support/DeskPuff/Styles/lighters/<id>/`，`type` 填写 `lighter`，`paletteBase` 可用 `silver-flint`、`warm-brass` 或 `midnight-enamel`。外观可以提供 `artwork.whole` 透明 PNG，也可以只设置 `palette.body`（外壳渐变）、`palette.rim`（金属细节渐变）和 `palette.flame`（火焰渐变）。没有贴图时只用这三个配色字段即可生成完整样式。

```json
{
  "schemaVersion": 1,
  "type": "lighter",
  "id": "my-brass-lighter",
  "name": "我的黄铜打火机",
  "author": "作者名",
  "license": "CC BY 4.0",
  "paletteBase": "warm-brass",
  "palette": {
    "body": ["#C69A50", "#64451E", "#A97932"],
    "rim": ["#F2D28C", "#795421"],
    "flame": ["#FF5B08", "#FFC52D", "#FFF3C4"]
  }
}
```

`id` 只能使用小写英文字母、数字和连字符，长度最多 64；安装文件夹名必须完全等于 `id`。`type` 为 `cigarette`、`cigaretteBox` 或 `ashtray`。香烟必须提供 `diameterMM`、`paper`、`filter` 和 `smoke`：直径范围 5–11 mm，烟雾倍率范围 0.25–3，颜色格式为 `#RRGGBB`。`artwork.paper`、`artwork.filter` 和 `artwork.preview` 可选。每种最多检查 100 个目录；无效 JSON、路径、颜色或图片会跳过，不会影响内置样式。符号链接和包外图片路径会被拒绝。

## 用图像生成或编程助手制作

可以把本页、schema 和样例 manifest 提供给 CodeIgnite、ChatGPT、Claude、Cursor 等工具，并让它们只生成透明 PNG 与 JSON。完成后检查：

1. 文件夹名与 manifest 的 `id` 完全一致。
2. `artwork` 中每个文件路径都指向包内真实存在的 PNG。
3. 烟盒贴图只包含盒身正面和盒盖外侧印刷；烟灰缸贴图不包含应用投影或额外的旋转按钮。
4. 烟灰缸内盆区域与 `geometry.basin` 对齐。
5. `manifest.json` 能通过 [schema.json](schema.json) 校验。

真实品牌包装的图形或标志应由提交者确认自己有权使用。DeskPuff 不会随应用附带第三方品牌素材。
