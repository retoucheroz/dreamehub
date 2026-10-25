# Build / Derleme

Apple Silicon · macOS 13+ · Swift 5.9 or later / veya üzeri.

```sh
git clone https://github.com/retoucheroz/dreamehub.git
cd dreamehub
bash build-app.sh
open "build/Dreame Hub Swift.app"
```

The local build and downloadable v0.2.1 DMG are ad-hoc signed, not notarized. The public build uses neutral artwork; official product artwork and icon are not redistributed as application assets.

Yerel derleme ve indirilebilir v0.2.1 DMG ad-hoc imzalıdır; Apple noter onayı yoktur. Genel kaynak sürümü nötr görseller kullanır; resmi ürün görselleri ve ikon uygulama varlığı olarak dağıtılmaz.

## Optional custom audio conversion / İsteğe bağlı ses dönüştürme

The app looks for an independently installed Apple Silicon libsndfile at `/opt/homebrew/lib/libsndfile.dylib`. If Homebrew is already installed, `brew install libsndfile` supplies it. Without it, audio conversion reports an unavailable dependency. No codec binary or original voice archive is bundled. See [third-party notices](../THIRD_PARTY_NOTICES.md).

Uygulama bağımsız kurulan Apple Silicon libsndfile kitaplığını `/opt/homebrew/lib/libsndfile.dylib` konumunda arar. Homebrew kuruluysa `brew install libsndfile` ile edinilebilir. Kitaplık yoksa ses dönüştürme bağımlılığın eksik olduğunu bildirir. Codec ikilisi veya özgün ses arşivleri pakete dahil değildir.

## Checks / Kontroller

```sh
swift test
node Tests/JS/MapPresentationTests.js
node Tests/JS/RobotMotionTests.js
node Tests/JS/MapRefreshTests.js
node Tests/JS/LocalizationTests.js
open "build/Dreame Hub Swift.app" --args --read-only
```

Read-only mode blocks device mutations. Automated tests do not replace physical-device verification. / Yalnız okuma modu cihaz değişikliklerini engeller. Otomatik testler fiziksel cihaz doğrulamasının yerini tutmaz.
