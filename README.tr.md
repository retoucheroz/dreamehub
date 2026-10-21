# Dreame Hub

### Dreame’in, artık Mac’inde.

Türkçe · [English](README.md) · [Italiano](README.it.md) · [Svenska](README.sv.md)

[![macOS için indir](https://img.shields.io/badge/macOS_i%C3%A7in_indir-Apple_Silicon-3478F6?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/retoucheroz/dreamehub/releases/download/v0.2.3/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg)

**[v0.2.3 DMG indir](https://github.com/retoucheroz/dreamehub/releases/download/v0.2.3/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg)** · macOS 13+ · M1/M2/M3/M4 ve sonraki Apple Silicon Mac’ler. DMG’yi aç, uygulamayı Applications klasörüne sürükle, başlat ve menü çubuğundaki ikonunu kullan. Bu önizleme ad-hoc imzalıdır; Apple noter onayı yoktur. İlk açılışta Gizlilik ve Güvenlik bölümünden onay gerekebilir. Bu indirme Intel Mac’leri desteklemez. [Sürüm notları](https://github.com/retoucheroz/dreamehub/releases/tag/v0.2.3).

**MOVA Home desteği (önizleme), v0.2.3'te ürün görselleriyle.** Girişte Dreame Home veya MOVA Home seçilebilir. MOVA kataloğu 22 model ailesini / 84 tam kimliği tanır ve üreticiden alınan 21 şeffaf ürün PNG'sini içerir; AI ile üretilmiş benzerleri kullanılmaz. **Entegrasyon henüz gerçek MOVA hesabı veya robotuyla doğrulanmadı:** canlı giriş, harita ve fiziksel kontroller doğrulama bekliyor. MOVA için hedefe gitme açık değildir. [MOVA ayrıntıları ve sınırlar](docs/MOVA.md).

Robotunu kontrol et, haritasını keşfet, gördüğü nesneleri incele. Hepsi macOS menü çubuğundan açılan sade bir panelde. **Robota root gerekmez. Python çalıştırılmaz.** Swift ile geliştirilir; mevcut arayüz Apple WKWebView içinde korunur.

![Dreame Hub özet ekranı ve temizlik kontrolleri](docs/media/app-overview.jpg)

## Temizliğin kontrolü elinin altında

**Menü çubuğundan tek tıkla.** Pili ve temizlik ilerlemesini gör, emiş ve mop ayarlarını seç; temizliği başlat, duraklat, durdur veya robotu istasyonuna gönder. Mop yıkama, kurutma ve hazne boşaltma işlemlerine aynı panelden ulaş.

**Evine farklı bir açıdan bak.** 3D haritayı yakınlaştır, döndür ve incele. Önceki temizliklere dön, kayıtlı rotayı gör veya haritada bir hedef seç. Robot simgesi alınan gerçek konum ve yönler arasında yumuşakça ilerler; veri gelmediğinde son ölçümde durur, hareket uydurmaz.

![Dreame Hub harita görünümü](docs/media/map.jpg)

**Robotunun fark ettiklerini gör.** Kayıtlı nesne algılarını ve varsa fotoğraflarını doğrudan haritadan aç. Fotoğraf erişimi robota ve kaydın içeriğine bağlıdır.

![Kayıtlı nesnenin fotoğrafı](docs/media/photo.jpg)

**Robotunun sesini kişiselleştir.** Anonsları listele, Mac üzerinde dinle ve kendi ses dosyalarınla değiştirmek için özel paket hazırla. Fırça, filtre ve istasyon bakımını da aynı uygulamadan takip et.

![Ses önizlemeleri ve özel ses kontrolleri](docs/media/voice.jpg)

## Dreame Hub ile tanış

https://github.com/user-attachments/assets/34265f51-2408-4933-bf6e-4cab9219fc7f

Tanıtımda gerçek arayüz ve kayıtlı harita kullanılır. Robot hareketi çekim için simüle edilmiştir.

## Başlangıç

[Görsel kurulum ve macOS güvenlik rehberi](docs/INSTALL.md) · [Giriş ve sunucu bölgesi yardımı](docs/LOGIN-REGIONS.md)

![Applications’a taşıma ve macOS engellerse yalnız bu uygulama için açılış onayı](docs/media/install-guide.svg)

**Giriş:** önce robotunun kayıtlı olduğu uygulamayı—Dreame Home veya MOVA Home—ardından hesabının sunucusunu seç; bu her zaman yaşadığın ülke değildir. Doğru Dreame hesabıyla Avrupa girişi reddediliyor veya robot görünmüyorsa Singapur / Diğer alternatif olabilir. ABD, Çin ve Rusya da o sunucularda kayıtlı hesaplar içindir. Kayıtlı sağlayıcı, kullanıcı adı veya bölge değişirse parola yeniden istenir; eski hesap sessizce kullanılmaz. [Tüm seçenekler ve çözüm adımları](docs/LOGIN-REGIONS.md).

Apple Silicon Mac, macOS 13 veya üzeri ve Dreame Home ya da MOVA Home hesabı gerekir. Giriş yap, robotunu seç ve menü çubuğu ikonundan Dreame Hub’ı aç. Seçilen sağlayıcı dahil hesap bilgileri macOS Anahtar Zinciri’nde kalır. Önceden kaydedilmiş Dreame hesaplarıyla uyumluluk korunur.

Kaynaktan derlemek için uyumlu Swift araçlarını kur ve çalıştır:

```sh
bash build-app.sh
open "build/Dreame Hub Swift.app"
```

Robota komut göndermeden incelemek için açılış komutuna `--args --read-only` ekle. Özel ses dönüştürme isteğe bağlı yerel libsndfile kurulumunu kullanır; [derleme ayrıntıları](docs/BUILD.md).

## Cihaz uyumluluğuna katkıda bulun

Dreame Hub’ı robotunuzla denediniz mi? Diğer kullanıcıların hangi özelliklerin çalıştığını görebilmesi için [modelinizin sonuçlarını paylaşın](https://github.com/retoucheroz/dreamehub/issues/new?template=device-report.yml). [Katkı rehberi](CONTRIBUTING.md).

## Modeller

Model kataloğunda **L10s Pro Ultra Heat, L20 Ultra, L40/L40s Ultra, L50 Ultra, L60 Ultra, X40/X50/X60 Ultra, Matrix10, Aqua10, D20 ve D30 çeşitleri** bulunur. [Tam model listesi ve özellik kapsamı](docs/SUPPORTED-MODELS.md).

MOVA önizleme kataloğu **E20/E30/E40/E50, M1, MOBIUS 60, P50/P70, S10/S70, V50/V70 ve Z50/Z60/Z70 çeşitlerini** ekler. Modeli tanımak, gerçek cihaz desteğinin test edildiği anlamına gelmez. Tam kimliği tanınan modellerde gömülü şeffaf ürün PNG'si, bilinmeyenlerde nötr görsel kullanılır. Renk temsili ürün rengidir; cihazdan algılanmış değildir. Üçüncü taraf görselleri kodun MIT lisansından ayrıdır; [görsel kaynakları](Sources/DreameHub/Resources/assets/products/mova/SOURCES.json).

<sub>Swift önizlemesi bir L10s Pro Ultra Heat üzerinde yalnız okuma ile kontrol edildi. Fiziksel komutlar ve hareket hâlindeki güncelleme gecikmesi Swift’te henüz canlı doğrulanmadı. 3D görünüm gerçek 2D haritanın perspektifidir; ham 3D LiDAR veya kamera akışı değildir. [Doğrulama ayrıntıları](docs/VERIFICATION.md).</sub>

---

Dreame, MOVA veya Apple ile bağlantılı olmayan, bağımsız bir uygulamadır. Özellikler modele göre değişir. MOVA ürün görselleri üçüncü taraf materyalidir; MIT lisanslı kod kapsamında değildir. Tanıtım özel uygulamanın gerçek arayüzünden kaydedildi. [Üçüncü taraf bildirimleri](THIRD_PARTY_NOTICES.md) · [MIT lisansı](LICENSE).
