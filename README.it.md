# Dreame Hub

### Il tuo Dreame. A casa sul tuo Mac.

[Türkçe](README.tr.md) · [English](README.md) · Italiano · [Svenska](README.sv.md)

[![Scarica per macOS](https://img.shields.io/badge/Download_for_macOS-Apple_Silicon-3478F6?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/retoucheroz/dreamehub/releases/download/v0.2.3/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg)

**[Scarica il DMG v0.2.3](https://github.com/retoucheroz/dreamehub/releases/download/v0.2.3/Dreame-Hub-Swift-0.2.3-preview-arm64.dmg)** · macOS 13+ · Apple Silicon M1/M2/M3/M4 o successivi. Apri il DMG, trascina l’app in Applicazioni, poi avviala e usa l’icona nella barra dei menu. Questa anteprima ha una firma ad hoc e non è autenticata da Apple; macOS potrebbe richiedere l’approvazione in Privacy e sicurezza. Questo download non supporta i Mac con processore Intel. [Note di rilascio](https://github.com/retoucheroz/dreamehub/releases/tag/v0.2.3).

**Supporto MOVA Home (anteprima), ora con le immagini dei prodotti nella v0.2.3.** Al login scegli Dreame Home o MOVA Home. Il catalogo MOVA riconosce 22 famiglie di modelli / 84 identificativi esatti e include 21 PNG trasparenti dei prodotti forniti dal produttore, non sostituti generati con l’IA. **Questa integrazione non è ancora stata verificata con un account o un robot MOVA reali:** login in tempo reale, mappe e controlli fisici restano non verificati. La navigazione verso una destinazione non è attiva per MOVA. [Dettagli e limitazioni MOVA](docs/MOVA.md).

Controlla il tuo robot, esplora la sua mappa e guarda cosa ha trovato, da un pannello compatto nella barra dei menu di macOS. **Nessun root del robot. Nessun runtime Python.** Realizzato in Swift, mantenendo l’interfaccia consolidata in WKWebView di Apple.

![Panoramica di Dreame Hub e controlli di pulizia](docs/media/app-overview.jpg)

## Una visione più pulita della pulizia

**A un clic dalla barra dei menu.** Controlla la batteria e l’avanzamento della pulizia, scegli aspirazione e impostazioni del mop, poi avvia, metti in pausa, interrompi o rimanda il robot alla base. Le scorciatoie della base tengono a portata di mano lavaggio, asciugatura e svuotamento.

**La tua casa, da un’altra prospettiva.** Ingrandisci, ruota ed esplora la mappa 3D. Rivedi le pulizie precedenti, esamina il percorso registrato o scegli una destinazione sulla mappa. Il movimento del robot viene interpolato in modo fluido tra le posizioni e le direzioni ricevute, poi si ferma all’ultima osservazione: nessun movimento inventato quando gli aggiornamenti si interrompono.

![Mappa di Dreame Hub](docs/media/map.jpg)

**Guarda cosa ha notato il tuo robot.** Apri i rilevamenti di oggetti registrati e le foto disponibili direttamente dalla mappa. La disponibilità dipende dal robot e dal record salvato.

![Foto di un oggetto registrato](docs/media/photo.jpg)

**Dai una voce al tuo robot.** Sfoglia gli annunci vocali, ascoltane l’anteprima sul Mac e prepara sostituzioni audio personalizzate. Tieni sotto controllo spazzole, filtri e manutenzione della base nella stessa app.

![Anteprime vocali e controlli per i suoni personalizzati](docs/media/voice.jpg)

## Scopri Dreame Hub

https://github.com/user-attachments/assets/34265f51-2408-4933-bf6e-4cab9219fc7f

Il filmato del prodotto usa l’interfaccia reale e una mappa registrata. Il movimento del robot è simulato per le riprese.

## Per iniziare

[Guida illustrata all’installazione e alla sicurezza di macOS](docs/INSTALL.md) · [Aiuto per login e regione del server](docs/LOGIN-REGIONS.md)

![Copia in Applicazioni e approva solo questa app se macOS la blocca](docs/media/install-guide.svg)

**Login:** scegli l’app in cui è registrato il robot, Dreame Home o MOVA Home, poi il server del tuo account, che non è necessariamente il Paese in cui ti trovi. Se Europa rifiuta un account Dreame verificato o non mostra alcun robot, l’alternativa corretta potrebbe essere Singapore / Altro. Sono disponibili anche USA, Cina e Russia per gli account registrati lì. Se modifichi il provider, il nome utente o la regione salvati, ora devi inserire di nuovo la password; il vecchio account non viene riutilizzato silenziosamente. [Tutte le opzioni e risoluzione dei problemi](docs/LOGIN-REGIONS.md).

Richiede un Mac con Apple Silicon, macOS 13 o successivo e un account Dreame Home o MOVA Home. Accedi, scegli il tuo robot e apri Dreame Hub dalla sua icona nella barra dei menu. Le credenziali salvate, incluso il provider scelto, restano nel Portachiavi di macOS. Gli account Dreame già salvati restano compatibili.

Per compilare dal codice sorgente, installa una toolchain Swift compatibile ed esegui:

```sh
bash build-app.sh
open "build/Dreame Hub Swift.app"
```

Per esaminare l’app senza inviare comandi al robot, aggiungi `--args --read-only` al comando di avvio. La conversione audio personalizzata usa un’installazione locale opzionale di libsndfile; vedi i [dettagli di compilazione](docs/BUILD.md).

## Aiutaci ad ampliare la compatibilità dei dispositivi

Hai provato Dreame Hub con il tuo robot? [Condividi i risultati del tuo modello](https://github.com/retoucheroz/dreamehub/issues/new?template=device-report.yml) così gli altri proprietari potranno vedere cosa funziona. [Contribuisci](CONTRIBUTING.md).

## Modelli

Il catalogo dei modelli include le varianti **L10s Pro Ultra Heat, L20 Ultra, L40/L40s Ultra, L50 Ultra, L60 Ultra, X40/X50/X60 Ultra, Matrix10, Aqua10, D20 e D30**. [Elenco completo dei modelli e funzioni coperte](docs/SUPPORTED-MODELS.md).

Il catalogo MOVA in anteprima aggiunge le varianti **E20/E30/E40/E50, M1, MOBIUS 60, P50/P70, S10/S70, V50/V70 e Z50/Z60/Z70**. Il riconoscimento non implica un supporto hardware testato. I modelli riconosciuti esattamente mostrano i PNG trasparenti dei prodotti inclusi; i modelli sconosciuti mantengono un’immagine neutra di riserva. Il colore del prodotto è indicativo, non rilevato. Le immagini di terze parti sono separate dalla licenza MIT del codice; vedi le [fonti delle immagini](Sources/DreameHub/Resources/assets/products/mova/SOURCES.json).

<sub>Questa anteprima Swift è stata verificata in sola lettura su un L10s Pro Ultra Heat. I comandi fisici e la latenza con il robot in movimento non sono ancora stati verificati dal vivo in Swift. La vista 3D è una prospettiva della mappa 2D reale, non un LiDAR 3D grezzo né un flusso della fotocamera. [Dettagli della verifica](docs/VERIFICATION.md).</sub>

---

Software indipendente e non ufficiale; non affiliato a Dreame, MOVA o Apple. Le funzioni del prodotto variano in base al modello. Le immagini dei prodotti MOVA restano materiale di terze parti, non codice con licenza MIT. Le registrazioni promozionali mostrano l’interfaccia reale dell’app privata. [Note di terze parti](THIRD_PARTY_NOTICES.md) · [Licenza MIT](LICENSE).
