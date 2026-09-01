# CalendarCountdown · Kalender-Countdown

> Ein nativer macOS-Tracker für wichtige Termine. Apple Kalender bleibt die maßgebliche Datenquelle, während Benutzer, Widgets und KI-Agenten eine klare und portable Countdown-Ebene erhalten.

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Русский](README.ru.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

## Screenshots

<p align="center">
  <img src="Documentation/Images/app-window-demo.png" width="900" alt="Demo des CalendarCountdown-Hauptfensters">
</p>

<p align="center">
  <img src="Documentation/Images/widget-demo.png" width="720" alt="Demo des CalendarCountdown-Desktop-Widgets">
</p>

<p align="center">
  <img src="Documentation/Images/menu-bar-demo.png" width="420" alt="Demo der CalendarCountdown-Menüleiste">
</p>

> Alle dargestellten Kalender, Namen und Daten sind frei erfundene Demodaten; echte Benutzerinformationen sind nicht enthalten.

## Was ist CalendarCountdown?

CalendarCountdown ist keine weitere Kalenderdatenbank. Konten, Kalender, Ereignisse und Farben bleiben unter der Kontrolle von Apple Kalender. Das Projekt liest und schreibt vom Benutzer freigegebene Kalender über EventKit und konzentriert sich darauf, wichtige Termine sichtbar, berechenbar, exportierbar und automatisierbar zu machen.

## Kernfunktionen

- Liest freigegebene Apple-Kalender und behält deren Konten, Kategorien und Farben bei.
- Verfolgt Geburtstage, Jahrestage, Feiertage und einmalige wichtige Termine.
- Unterstützt jährliche Regeln nach gregorianischem und chinesischem Mondkalender, einschließlich Schaltmonaten und Ausgleich für kurze Mondmonate.
- Berechnet „heute“, „morgen“ und verbleibende Tage anhand des lokalen Systemkalenders.
- Native macOS-App, Menüleistenansicht und WidgetKit-Desktop-Widget.
- App, Menüleisten-Popover und Widgets folgen der macOS-Sprache auf vereinfachtem Chinesisch, Englisch, Japanisch, Koreanisch, Spanisch oder Russisch.
- Fügt normale Ereignisse sowie gregorianische oder lunare Geburtstage einem ausdrücklich gewählten Apple-Kalender hinzu.
- Exportiert alle aktuell verfolgten wichtigen Termine mit einem Klick.
- Universal Binary für Apple-Silicon- und Intel-Macs ab macOS 14.

## Für KI-Agenten entwickelt

`calcount` ist eine lokale CLI, die direkt als Shell-Werkzeug eines Agenten bereitgestellt werden kann. Alle strukturierten Befehle geben JSON ohne interaktive Texte aus. Eindeutige Exit-Codes unterscheiden Bedienfehler, fehlende Kalenderberechtigung und Laufzeitfehler.

Agentenfreundliche Eigenschaften:

- **Vorhersehbares Lesen:** Kalender auflisten, Ereignisse abfragen, nächste Countdowns und den Tracking-Index abrufen.
- **Stabile JSON-Hüllen:** Erfolg als `{ "ok": true, "data": ... }`, Fehler als `{ "ok": false, "error": { "code": ..., "message": ... } }`.
- **Prüfbares Schreiben:** Schreibvorgänge erfordern einen expliziten Apple-Kalender; Massenimporte unterstützen `--dry-run`.
- **Idempotente Importe:** `externalId` verhindert Duplikate, wenn ein Agent eine Anfrage wiederholt.
- **Portabler Kontext:** `tracked-events.json` bewahrt Startjahr, Kalendersystem, Monat, Tag, Wiederholungsregeln, nächsten Termin und Apple-Kalender-Referenzen.
- **Local First:** Kein Server und keine Kalenderkopie in der Cloud; Zugriff erfolgt nur auf freigegebene EventKit-Daten des aktuellen Macs.

Häufige Lese- und Exportbefehle:

```bash
./calcount doctor
./calcount calendars list
./calcount events list --days 365
./calcount next --limit 10 --days 3653
./calcount tracking refresh
./calcount tracking list
./calcount tracking export --output tracked-events.json
```

Ein Agent kann die Ausgabe direkt mit `jq` verarbeiten:

```bash
./calcount next --limit 5 | jq '.data[] | {title, eventDate, calendarTitle}'
```

Massenimport vor dem Schreiben prüfen:

```bash
./calcount import /path/to/import.json --dry-run
```

`calcount` stellt derzeit einen lokalen CLI-Vertrag bereit. Es beansprucht nicht, ein MCP-Server oder eine Remote-API zu sein, kann aber von jedem Agenten-Framework mit Shell-Tool-Calling eingebunden werden.

## Tracking-JSON

Apple Kalender bleibt immer die maßgebliche Quelle für Ereignisinhalte. `tracked-events.json` ist keine zweite Kalenderdatenbank, sondern ein versionierter, exportierbarer Index der aktuell im Countdown sichtbaren Einträge.

Jeder Eintrag enthält:

- Stabile UUID, Titel und Typ: Geburtstag, Jahrestag, wichtiger Termin oder Sonstiges.
- Startjahr, Monat, Tag und Kennzeichnung für gregorianischen/lunaren Kalender.
- Wiederholungsfrequenz, Wiederholungskalender und Regeln für lunare Grenzfälle.
- Nächsten Termin, Uhrzeit, Zeitzone und Ganztagsstatus.
- Apple-Kalender-Quelle, Kalender, Farbe und IDs zum erneuten Verknüpfen.
- Tracking-Modus, Beginn des Trackings und angehefteter Status.

Das vollständige anonymisierte Beispiel steht in [tracked-events.example.json](Documentation/tracked-events.example.json).

## Installation

Aktuelle Version: **1.0.1**

1. [CalendarCountdown-1.0.1-macos-universal.dmg von GitHub Releases herunterladen](https://github.com/MyKWK/CalendarCountdown/releases/download/v1.0.1/CalendarCountdown-1.0.1-macos-universal.dmg).
2. CalendarCountdown nach Programme ziehen.
3. Die App starten und vollständigen Zugriff auf Apple Kalender erlauben.

Version 1.0.1 ist derzeit ad-hoc signiert, nicht mit einer Apple Developer ID signiert und nicht notarisiert. Beim ersten Start muss die App eventuell im Finder mit gedrückter Control-Taste angeklickt und „Öffnen“ gewählt werden.

## Aus dem Quellcode bauen

Erfordert macOS 14+, Xcode und [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd Source
./Scripts/bootstrap.sh
./Scripts/build.sh
xcodebuild -project CalendarCountdown.xcodeproj -scheme CalendarCountdown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
./Scripts/package-dmg.sh
```

## Daten- und Datenschutzgrenzen

- Kalenderereignisse bleiben in Apple Kalender; das Projekt betreibt keinen eigenen Cloud-Kalenderdienst.
- Tracking-Auswahl und `tracked-events.json` bleiben zur Anzeige und zum benutzergesteuerten Export auf dem Mac.
- Schreibvorgänge betreffen nur den ausdrücklich gewählten Apple-Kalender.
- Echte persönliche Termindateien werden per `.gitignore` ausgeschlossen und dürfen nicht in das öffentliche Repository oder Release-Paket gelangen.

## Aktueller Umfang

- Derzeit wird macOS unterstützt. iPhone-App, iPhone-Widgets und CloudKit-Regelsynchronisierung sind zukünftige Arbeiten.
- Das Projekt ist kein CalDAV-Server und dupliziert nicht die Konto- oder Kategorienstruktur von Apple Kalender.
- Der ausführliche Produkt- und Datenvertrag steht in [Documentation/PRODUCT.md](Documentation/PRODUCT.md).

## Repository-Struktur

- `Source/`: Swift-Quellcode, XcodeGen-Konfiguration, Tests und Build-Skripte.
- `Documentation/`: Produktvertrag, Installationshinweise und anonymisierte JSON-Beispiele.
- `Releases/1.0.1/`: Versionshinweise und SHA-256-Prüfsumme; das DMG wird über GitHub Releases verteilt.

## Lizenz

Dieses Projekt steht unter der [MIT-Lizenz](LICENSE).
