# Kurulum / Installation

![Görsel kurulum adımları / Illustrated installation steps](media/install-guide.svg)

## Türkçe

1. DMG’yi yalnız [resmî proje Releases sayfasından](https://github.com/retoucheroz/dreamehub/releases) indir. Apple Silicon (M1 ve sonrası), macOS 13+ gerekir; Intel paketi değildir.
2. DMG’yi açıp **Dreame Hub Swift.app** dosyasını **Applications / Uygulamalar** klasörüne sürükle. Uygulamayı bu klasörden bir kez açmayı dene.
3. Geliştirici doğrulanamadığı için engellenirse ve dosyanın kaynağına güveniyorsan ** → Sistem Ayarları → Gizlilik ve Güvenlik** bölümünde aşağıdaki **Güvenlik → Yine de Aç** düğmesini kullan. Düğme, açma denemesinden sonra görünür; gerekirse yeniden açmayı dene. macOS sürümüne göre düğmenin adı farklı görünebilir.
4. Açılan uyarıda uygulama adını kontrol edip **Aç** ile onayla. İstenirse Touch ID veya Mac parolanı kullan; bu, Dreame hesap parolan değildir. Ardından uygulama menü çubuğundaki ikonundan açılır.

**Neden uyarı var?** Bu önizleme ad-hoc imzalıdır; Apple Developer ID / noter onayı yoktur. Apple uygulamanın güvenli olduğunu doğrulamış değildir. Yalnız kaynağına güvendiğin dosyayı aç. **Gatekeeper veya SIP’yi kapatma; karantina kaldırma komutları çalıştırma.** “Bilgisayarınıza zarar verecek”, zararlı yazılım veya hasarlı dosya uyarısını bu adımlarla geçmeye çalışma; dur, yeniden resmî kaynaktan indir ve sürümdeki SHA256SUMS.txt ile bütünlüğünü kontrol et. Kurumsal Mac’lerde onay BT yöneticisine bağlı olabilir.

**Diğer izinler:** Normal kullanım için Erişilebilirlik, Ekran Kaydı veya Tam Disk Erişimi istemiyoruz. Kayıtlı hesabına erişirken Anahtar Zinciri onayı çıkarsa uygulama adını kontrol et. Özel ses paketi aktarımında yerel ağ bağlantısı gerekebilir; böyle bir macOS istemi yalnız bu işlevi kullanırken anlamlıdır. Temel kontrol için Homebrew gerekmez; özel ses dönüştürme libsndfile ister. [Derleme ve bağımlılıklar](BUILD.md).

Girişte robot görünmüyor veya hesap reddediliyorsa: [Ülke / sunucu bölgesi rehberi](LOGIN-REGIONS.md).

Kaynak: [Apple — Mac’inizde uygulamaları güvenle açma](https://support.apple.com/tr-tr/102445). Şema gerçek sistem ekran görüntüsü değildir.

## English

1. Download the DMG only from [this project's Releases page](https://github.com/retoucheroz/dreamehub/releases). Requires Apple Silicon (M1 or later), macOS 13+; this is not an Intel build.
2. Open it and drag **Dreame Hub Swift.app** into **Applications**. Try launching it from Applications once.
3. If macOS blocks it because the developer cannot be verified, and you trust the source, open ** → System Settings → Privacy & Security → Security → Open Anyway**. The app-specific option appears after an attempted launch. Names/layout may differ by macOS version.
4. Check the app name, confirm **Open**, and authenticate with Touch ID or your Mac password if requested. This is not your Dreame password. Use the app's menu-bar icon afterward.

This preview is ad-hoc signed, without Apple Developer ID/notarization. Apple has not verified its safety. **Do not disable Gatekeeper or SIP or remove quarantine using terminal commands.** Do not override malware, “will damage your computer”, or damaged-file alerts; stop, obtain a fresh official download and check it against SHA256SUMS.txt. Managed Macs may require IT approval.

Normal use does not require Accessibility, Screen Recording or Full Disk Access. Check the app name if Keychain requests access to saved credentials. Local network access may be needed for custom voice-package transfer. Basic controls do not require Homebrew; optional audio conversion uses libsndfile. [Dependencies](BUILD.md) · [Login and server regions](LOGIN-REGIONS.md).

Source: [Apple — Safely open apps on your Mac](https://support.apple.com/en-us/102445). The diagram is an illustration, not a system screenshot.

## Italiano

1. Scarica il DMG solo dalla [pagina Releases di questo progetto](https://github.com/retoucheroz/dreamehub/releases). Richiede Apple Silicon (M1 o successivo) e macOS 13+; non è una build per Intel.
2. Aprilo e trascina **Dreame Hub Swift.app** in **Applicazioni**. Prova ad avviarla una volta da Applicazioni.
3. Se macOS la blocca perché non è possibile verificare lo sviluppatore e ti fidi della fonte, apri ** → Impostazioni di Sistema → Privacy e sicurezza → Sicurezza → Apri comunque**. L’opzione specifica per l’app compare dopo un tentativo di avvio. Nomi e disposizione possono variare in base alla versione di macOS.
4. Controlla il nome dell’app, conferma con **Apri** e, se richiesto, autenticati con Touch ID o con la password del Mac. Non è la password di Dreame. Poi usa l’icona dell’app nella barra dei menu.

Questa anteprima ha una firma ad hoc, senza Apple Developer ID né autenticazione notarile. Apple non ne ha verificato la sicurezza. **Non disattivare Gatekeeper o SIP e non rimuovere la quarantena con comandi da Terminale.** Non ignorare gli avvisi di malware, di file danneggiato o “danneggerà il computer”; fermati, scarica di nuovo una copia ufficiale e confrontala con SHA256SUMS.txt. Sui Mac gestiti potrebbe servire l’approvazione del reparto IT.

L’uso normale non richiede Accessibilità, Registrazione schermo o Accesso completo al disco. Se il Portachiavi chiede l’accesso alle credenziali salvate, controlla il nome dell’app. Per il trasferimento del pacchetto vocale personalizzato può servire l’accesso alla rete locale. I controlli di base non richiedono Homebrew; la conversione audio opzionale usa libsndfile. [Dipendenze](BUILD.md) · [Login e regioni del server](LOGIN-REGIONS.md).

Fonte: [Apple — Aprire app in modo sicuro sul Mac](https://support.apple.com/it-it/102445). Lo schema è un’illustrazione, non un’istantanea del sistema.

## Svenska

1. Hämta DMG-filen endast från [projektets Releases-sida](https://github.com/retoucheroz/dreamehub/releases). Kräver Apple Silicon (M1 eller senare) och macOS 13+; det här är inte en version för Intel.
2. Öppna den och dra **Dreame Hub Swift.app** till **Program**. Försök att öppna appen från Program en gång.
3. Om macOS blockerar appen eftersom utvecklaren inte kan verifieras, och du litar på källan, öppnar du ** → Systeminställningar → Integritet och säkerhet → Säkerhet → Öppna ändå**. Alternativet för just den här appen visas efter ett försök att öppna den. Namn och layout kan skilja sig mellan olika versioner av macOS.
4. Kontrollera appens namn, bekräfta med **Öppna** och autentisera med Touch ID eller ditt Mac-lösenord om du ombeds. Det är inte ditt Dreame-lösenord. Använd sedan appens symbol i menyraden.

Den här förhandsversionen är ad hoc-signerad, utan Apple Developer ID/notarisering. Apple har inte verifierat att den är säker. **Stäng inte av Gatekeeper eller SIP och ta inte bort karantänattributet med terminalkommandon.** Kringgå inte varningar om skadlig programvara, ”kommer att skada datorn” eller skadade filer; avbryt, hämta en ny officiell kopia och kontrollera den mot SHA256SUMS.txt. Hanterade Mac-datorer kan kräva godkännande från IT-avdelningen.

Normal användning kräver inte Hjälpmedel, Skärminspelning eller Fullständig skivåtkomst. Kontrollera appens namn om Nyckelring begär åtkomst till sparade inloggningsuppgifter. Åtkomst till lokalt nätverk kan behövas för att överföra ett anpassat röstpaket. Grundläggande kontroller kräver inte Homebrew; valfri ljudkonvertering använder libsndfile. [Beroenden](BUILD.md) · [Inloggning och serverregioner](LOGIN-REGIONS.md).

Källa: [Apple – Öppna appar säkert på din Mac](https://support.apple.com/sv-se/102445). Diagrammet är en illustration, inte en skärmbild från systemet.
