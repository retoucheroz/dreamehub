# Dreame Hub

### Din Dreame. Hemma på din Mac.

[Türkçe](README.tr.md) · [English](README.md) · [Italiano](README.it.md) · Svenska

[![Hämta för macOS](https://img.shields.io/badge/Download_for_macOS-Apple_Silicon-3478F6?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/retoucheroz/dreamehub/releases/download/v0.2.3/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg)

**[Hämta DMG för v0.2.3](https://github.com/retoucheroz/dreamehub/releases/download/v0.2.3/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg)** · macOS 13+ · M1/M2/M3/M4 eller senare Apple Silicon. Öppna DMG-filen, dra appen till Program, starta den och använd symbolen i menyraden. Den här förhandsversionen är ad hoc-signerad, inte notariserad av Apple; macOS kan kräva att du godkänner den i Integritet och säkerhet. Intel-baserade Mac-datorer stöds inte av den här nedladdningen. [Versionsinformation](https://github.com/retoucheroz/dreamehub/releases/tag/v0.2.3).

**Stöd för MOVA Home (förhandsversion), nu med produktbilder i v0.2.3.** Välj Dreame Home eller MOVA Home vid inloggningen. MOVA-katalogen känner igen 22 modellfamiljer / 84 exakta identifierare och innehåller 21 transparenta produkt-PNG:er från tillverkaren – inte AI-genererade ersättningar. **Inget riktigt MOVA-konto eller robot har ännu använts för att verifiera integrationen:** live-inloggning, kartor och fysiska kontroller är fortfarande overifierade. Målnavigering är inte aktiverad för MOVA. [MOVA-detaljer och begränsningar](docs/MOVA.md).

Styr din robot, utforska dess karta och se vad den har hittat – från en kompakt panel i menyraden i macOS. **Ingen rootning av roboten. Ingen Python-körmiljö.** Byggd med Swift, med det beprövade gränssnittet bevarat i Apples WKWebView.

![Dreame Hubs översikt och städkontroller](docs/media/app-overview.jpg)

## En renare bild av städningen

**Ett klick från menyraden.** Kontrollera batteri och städförlopp, välj sugeffekt och moppinställningar och starta, pausa, stoppa eller skicka hem roboten. Genvägar till basstationen gör tvätt, torkning och tömning lättillgängliga.

**Ditt hem från en ny vinkel.** Zooma, rotera och utforska 3D-kartan. Gå igenom tidigare städningar, granska den registrerade rutten eller välj ett mål på kartan. Robotens rörelse glider mjukt mellan mottagna positioner och riktningar och stannar sedan vid den senaste observationen – ingen påhittad rörelse när uppdateringarna upphör.

![Dreame Hubs karta](docs/media/map.jpg)

**Se vad roboten lade märke till.** Öppna registrerade objektdetekteringar och tillgängliga foton direkt från kartan. Tillgängligheten beror på roboten och den sparade posten.

![Foto av ett registrerat objekt](docs/media/photo.jpg)

**Ge roboten en röst.** Bläddra bland röstmeddelanden, förhandslyssna på dem på din Mac och förbered egna ersättningsljud. Håll koll på borstar, filter och underhåll av basstationen i samma app.

![Förhandslyssning av röster och reglage för egna ljud](docs/media/voice.jpg)

## Möt Dreame Hub

https://github.com/user-attachments/assets/34265f51-2408-4933-bf6e-4cab9219fc7f

Produktfilmen visar det verkliga gränssnittet och en registrerad karta. Robotens rörelser är simulerade för inspelningen.

## Kom igång

[Illustrerad guide för installation och macOS-säkerhet](docs/INSTALL.md) · [Hjälp med inloggning och serverregion](docs/LOGIN-REGIONS.md)

![Kopiera till Program och godkänn bara den här appen om macOS blockerar den](docs/media/install-guide.svg)

**Inloggning:** välj appen där roboten är registrerad – Dreame Home eller MOVA Home – och sedan kontots server, som inte nödvändigtvis är landet du befinner dig i. Om Europa avvisar ett verifierat Dreame-konto eller inte visar någon robot kan Singapore / Övriga vara rätt alternativ. USA, Kina och Ryssland finns också för konton som registrerats där. Om du ändrar sparad leverantör, användarnamn eller region måste du nu ange lösenordet igen; det gamla kontot återanvänds inte i tysthet. [Alla alternativ och felsökning](docs/LOGIN-REGIONS.md).

Kräver en Mac med Apple Silicon, macOS 13 eller senare och ett Dreame Home- eller MOVA Home-konto. Logga in, välj din robot och öppna Dreame Hub från symbolen i menyraden. Sparade inloggningsuppgifter, inklusive vald leverantör, stannar i Nyckelring i macOS. Befintliga sparade Dreame-konton fungerar fortfarande.

För att bygga från källkod installerar du en kompatibel Swift-verktygskedja och kör:

```sh
bash build-app.sh
open "build/Dreame Hub Swift.app"
```

För att granska utan att skicka robotkommandon lägger du till `--args --read-only` i startkommandot. Konvertering av egna ljud använder en valfri lokal installation av libsndfile; se [byggdetaljer](docs/BUILD.md).

## Hjälp till att utöka enhetskompatibiliteten

Har du provat Dreame Hub med din robot? [Dela resultaten för din modell](https://github.com/retoucheroz/dreamehub/issues/new?template=device-report.yml) så att andra ägare kan se vad som fungerar. [Bidra](CONTRIBUTING.md).

## Modeller

Modellkatalogen omfattar **varianter av L10s Pro Ultra Heat, L20 Ultra, L40/L40s Ultra, L50 Ultra, L60 Ultra, X40/X50/X60 Ultra, Matrix10, Aqua10, D20 och D30**. [Fullständig modellista och funktionstäckning](docs/SUPPORTED-MODELS.md).

MOVA-förhandskatalogen lägger till **varianter av E20/E30/E40/E50, M1, MOBIUS 60, P50/P70, S10/S70, V50/V70 och Z50/Z60/Z70**. Att en modell känns igen innebär inte att stödet har testats på riktig hårdvara. Exakt igenkända modeller visar medföljande transparenta produkt-PNG:er; okända modeller behåller en neutral reservbild. Produktfärgen är representativ, inte detekterad. Tredjepartsbilder omfattas inte av kodens MIT-licens; se [bildkällor](Sources/DreameHub/Resources/assets/products/mova/SOURCES.json).

<sub>Den här Swift-förhandsversionen har kontrollerats skrivskyddat på en L10s Pro Ultra Heat. Fysiska kommandon och latens för en robot i rörelse har ännu inte verifierats live i Swift. 3D-vyn är ett perspektiv av den verkliga 2D-kartan, inte rå 3D-LiDAR eller ett kameraflöde. [Verifieringsdetaljer](docs/VERIFICATION.md).</sub>

---

Oberoende, inofficiell programvara; inte ansluten till Dreame, MOVA eller Apple. Produktfunktionerna varierar mellan modeller. MOVA-produktbilderna är fortfarande tredjepartsmaterial, inte MIT-licensierad kod. Reklaminspelningarna visar den privata appens verkliga gränssnitt. [Meddelanden om tredje part](THIRD_PARTY_NOTICES.md) · [MIT-licens](LICENSE).
