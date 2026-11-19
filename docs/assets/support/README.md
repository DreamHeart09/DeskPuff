# Support and community QR codes

The public README uses the cropped images under `docs/assets/screenshots/`, while the app loads the bundled copies from `Sources/DeskPuff/Resources/Support/`:

- `AliPayQR.PNG` / `AlipayQR.PNG` — Alipay support code
- `wechatQR.JPG` / `WeChatQR.JPG` — WeChat support code
- `QQGroupQR.jpg` — DeskPuff player group, QQ group `207898947`

When replacing a QR code, update both locations, regenerate its README thumbnail under `docs/assets/screenshots/thumbs/`, and verify the code scans before publishing a build or page. The original QQ group poster is kept as `docs/assets/screenshots/QQGroupQR.jpg`; the app and README use a square crop for a more legible code.
