# Dreame Hub

### Your Dreame. At home on your Mac.

[Türkçe](README.tr.md) · English · [Italiano](README.it.md) · [Svenska](README.sv.md)

[![Download for macOS](https://img.shields.io/badge/Download_for_macOS-Apple_Silicon-3478F6?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/retoucheroz/dreamehub/releases/download/v0.2.3/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg)

**[Download v0.2.3 DMG](https://github.com/retoucheroz/dreamehub/releases/download/v0.2.3/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg)** · macOS 13+ · M1/M2/M3/M4 or later Apple Silicon. Open the DMG, drag the app into Applications, then launch it and use the menu-bar icon. This preview is ad-hoc signed, not Apple-notarized; macOS may require approval in Privacy & Security. Intel Macs are not supported by this download. [Release notes](https://github.com/retoucheroz/dreamehub/releases/tag/v0.2.3).

**MOVA Home support (preview), now with product images in v0.2.3.** Select Dreame Home or MOVA Home at login. The MOVA catalog recognizes 22 model families / 84 exact identifiers and includes 21 transparent manufacturer product PNGs—not AI-generated substitutes. **No real MOVA account or robot has been used to validate this integration yet:** live login, maps and physical controls remain unverified. MOVA target navigation is not enabled. [MOVA details and limitations](docs/MOVA.md).

Control your robot, explore its map and see what it found — from a compact macOS menu-bar panel. **No rooting the robot. No Python runtime.** Built with Swift, with the established interface preserved in Apple's WKWebView.

![Dreame Hub overview and cleaning controls](docs/media/app-overview.jpg)

## A cleaner view of cleaning

**One click from your menu bar.** Check battery and cleaning progress, choose suction and mop settings, then start, pause, stop or send your robot home. Station shortcuts keep washing, drying and emptying close at hand.

**Your home, from a different angle.** Zoom, rotate and explore the 3D map. Review previous cleans, inspect the recorded route or choose a target on the map. Robot movement eases between received positions and directions, then stops at the latest observation — no invented movement when updates stop.

![Dreame Hub map](docs/media/map.jpg)

**See what your robot noticed.** Open recorded object detections and available photos directly from the map. Availability depends on the robot and the saved record.

![Recorded object photo](docs/media/photo.jpg)

**Give your robot a voice.** Browse announcements, preview them on your Mac and prepare custom sound replacements. Keep track of brushes, filters and station maintenance in the same app.

![Voice previews and custom sound controls](docs/media/voice.jpg)

## Meet Dreame Hub

https://github.com/user-attachments/assets/34265f51-2408-4933-bf6e-4cab9219fc7f

The product film uses the actual interface and recorded map. Robot motion is simulated for the shoot.

## Get started

[Illustrated installation & macOS security guide](docs/INSTALL.md) · [Login and server-region help](docs/LOGIN-REGIONS.md)

![Copy to Applications and approve only this app if macOS blocks it](docs/media/install-guide.svg)

**Login:** select the app where your robot is registered—Dreame Home or MOVA Home—then your account's server, not necessarily your current country. If Europe rejects a verified Dreame account or shows no robot, Singapore / Other may be the correct alternative. USA, China and Russia are also available for accounts registered there. Changing the saved provider, username or region now requires re-entering the password; the old account is not silently reused. [All options and troubleshooting](docs/LOGIN-REGIONS.md).

Requires an Apple Silicon Mac, macOS 13 or later and a Dreame Home or MOVA Home account. Sign in, select your robot and open Dreame Hub from its menu-bar icon. Saved credentials, including the selected provider, stay in macOS Keychain. Existing saved Dreame accounts remain compatible.

For a source build, install a compatible Swift toolchain and run:

```sh
bash build-app.sh
open "build/Dreame Hub Swift.app"
```

For inspection without issuing robot commands, append `--args --read-only` to the launch command. Custom audio conversion uses an optional local libsndfile installation; see [build details](docs/BUILD.md).

## Help expand device compatibility

Tried Dreame Hub with your robot? [Share your model's results](https://github.com/retoucheroz/dreamehub/issues/new?template=device-report.yml) so other owners can see what works. [Contribute](CONTRIBUTING.md).

## Models

The model catalog includes **L10s Pro Ultra Heat, L20 Ultra, L40/L40s Ultra, L50 Ultra, L60 Ultra, X40/X50/X60 Ultra, Matrix10, Aqua10, D20 and D30 variants**. [Full model list and feature coverage](docs/SUPPORTED-MODELS.md).

The MOVA preview catalog adds **E20/E30/E40/E50, M1, MOBIUS 60, P50/P70, S10/S70, V50/V70 and Z50/Z60/Z70 variants**. Recognition is not a claim of tested hardware support. Exact recognized models show bundled transparent product PNGs; unknown models retain a neutral fallback. Product color is representative, not detected. Third-party artwork is separate from the code's MIT license; see [image sources](Sources/DreameHub/Resources/assets/products/mova/SOURCES.json).

<sub>This Swift preview was checked read-only on one L10s Pro Ultra Heat. Physical commands and moving-robot latency are not yet live-verified in Swift. The 3D view is a perspective of the real 2D map, not raw 3D LiDAR or a camera feed. [Verification details](docs/VERIFICATION.md).</sub>

---

Independent, unofficial software; not affiliated with Dreame, MOVA or Apple. Product capabilities vary by model. MOVA product artwork remains third-party material, not MIT-licensed code. Promotional recordings show the private app's actual interface. [Third-party notices](THIRD_PARTY_NOTICES.md) · [MIT license](LICENSE).
