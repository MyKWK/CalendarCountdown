# CalendarCountdown · Compte à rebours du calendrier

> Un outil macOS natif de suivi des dates importantes. Apple Calendar reste la source de vérité, tandis que les utilisateurs, les widgets et les agents IA disposent d’une couche de compte à rebours claire et portable.

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Português](README.pt.md) · [Deutsch](README.de.md) · [Français](README.fr.md)

## Captures d’écran

<p align="center">
  <img src="Documentation/Images/app-window-demo.png" width="900" alt="Démonstration de la fenêtre principale de CalendarCountdown">
</p>

<p align="center">
  <img src="Documentation/Images/widget-demo.png" width="720" alt="Démonstration du widget de bureau CalendarCountdown">
</p>

<p align="center">
  <img src="Documentation/Images/menu-bar-demo.png" width="420" alt="Démonstration de CalendarCountdown dans la barre des menus">
</p>

> Tous les calendriers, noms et dates affichés sont des données de démonstration fictives ; aucune information réelle d’utilisateur n’est incluse.

## Présentation

CalendarCountdown n’est pas une autre base de données de calendrier. Les comptes, calendriers, événements et couleurs restent gérés par Apple Calendar. Le projet lit et écrit les calendriers autorisés par l’utilisateur via EventKit, afin que les dates importantes restent visibles, calculables, exportables et faciles à automatiser.

## Fonctionnalités principales

- Lit les calendriers Apple autorisés tout en conservant leurs comptes, catégories et couleurs d’origine.
- Suit les anniversaires, commémorations, jours fériés et dates importantes non récurrentes.
- Prend en charge les règles annuelles grégoriennes et du calendrier lunaire chinois, y compris les mois intercalaires et le repli pour les mois courts.
- Calcule « aujourd’hui », « demain » et le nombre de jours restants avec le calendrier local du système.
- Application macOS native, aperçu dans la barre des menus et widget de bureau WidgetKit.
- Un anneau bleu permanent rend l’action d’actualisation facile à repérer dans la fenêtre principale comme dans le menu contextuel.
- Ajoute des événements ordinaires et des anniversaires grégoriens ou lunaires dans un calendrier Apple explicitement choisi.
- Exporte en un clic toutes les dates importantes actuellement suivies.
- Binaire universel pour les Mac Apple Silicon et Intel sous macOS 14 ou version ultérieure.

## Conçu pour les agents IA

`calcount` est une interface en ligne de commande locale qui peut être exposée directement comme outil shell d’un agent. Toutes les commandes structurées produisent du JSON sans texte interactif, et des codes de sortie explicites distinguent les erreurs d’utilisation, l’absence d’autorisation du calendrier et les erreurs d’exécution.

Propriétés adaptées aux agents :

- **Lectures prévisibles :** lister les calendriers, interroger les événements, obtenir les prochains comptes à rebours et lire l’index de suivi.
- **Enveloppes JSON stables :** succès avec `{ "ok": true, "data": ... }`, échec avec `{ "ok": false, "error": { "code": ..., "message": ... } }`.
- **Écritures contrôlables :** toute écriture exige un calendrier Apple explicite et les imports en lot prennent en charge `--dry-run`.
- **Imports idempotents :** `externalId` évite les doublons lorsqu’un agent réessaie une requête.
- **Contexte portable :** `tracked-events.json` conserve l’année initiale, le système de calendrier, le mois, le jour, la récurrence, la prochaine occurrence et les références Apple Calendar.
- **Local d’abord :** aucun serveur ni copie du calendrier dans le cloud ; seuls les données EventKit autorisées sur le Mac actuel sont consultées.

Commandes courantes de lecture et d’export :

```bash
./calcount doctor
./calcount calendars list
./calcount events list --days 365
./calcount next --limit 10 --days 3653
./calcount tracking refresh
./calcount tracking list
./calcount tracking export --output tracked-events.json
```

Un agent peut consommer directement le résultat avec `jq` :

```bash
./calcount next --limit 5 | jq '.data[] | {title, eventDate, calendarTitle}'
```

Prévisualiser un import avant toute écriture :

```bash
./calcount import /path/to/import.json --dry-run
```

`calcount` fournit actuellement un contrat CLI local. Il ne prétend pas être un serveur MCP ni une API distante, mais tout framework d’agent prenant en charge les outils shell peut l’encapsuler.

## JSON des dates suivies

Apple Calendar reste toujours la source de vérité du contenu des événements. `tracked-events.json` n’est pas une seconde base de données : c’est un index versionné et exportable des éléments actuellement visibles dans le compte à rebours.

Chaque entrée contient :

- UUID stable, titre et type : anniversaire, commémoration, date importante ou autre.
- Année initiale, mois, jour et indicateur grégorien/lunaire.
- Fréquence, calendrier de récurrence et règles pour les cas limites lunaires.
- Prochaine occurrence, heure, fuseau horaire et état « journée entière ».
- Source, calendrier, couleur et identifiants Apple Calendar pour réassociation.
- Mode de suivi, date de début du suivi et état épinglé.

Consultez l’exemple anonyme complet dans [tracked-events.example.json](Documentation/tracked-events.example.json).

## Installation

Version actuelle : **1.0.0**

1. [Téléchargez CalendarCountdown-1.0.0-macos-universal.dmg depuis GitHub Releases](https://github.com/MyKWK/CalendarCountdown/releases/download/v1.0.0/CalendarCountdown-1.0.0-macos-universal.dmg).
2. Faites glisser CalendarCountdown dans Applications.
3. Lancez l’app et accordez-lui l’accès complet à Apple Calendar.

La version 1.0.0 utilise actuellement une signature ad hoc ; elle n’est ni signée avec un Apple Developer ID ni notarisée. Au premier lancement, il peut être nécessaire de faire un Control-clic sur l’app dans le Finder, puis de choisir Ouvrir.

## Compiler depuis les sources

Nécessite macOS 14+, Xcode et [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd Source
./Scripts/bootstrap.sh
./Scripts/build.sh
xcodebuild -project CalendarCountdown.xcodeproj -scheme CalendarCountdown \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
./Scripts/package-dmg.sh
```

## Limites des données et de la confidentialité

- Les événements restent dans Apple Calendar ; le projet n’exploite aucun service de calendrier cloud propre.
- Les sélections et `tracked-events.json` restent sur le Mac pour l’affichage et l’export demandé par l’utilisateur.
- Les écritures n’affectent que le calendrier Apple explicitement choisi.
- Les vrais fichiers de dates personnelles sont exclus par `.gitignore` et ne doivent pas entrer dans le dépôt public ni dans le paquet de publication.

## Périmètre actuel

- macOS est pris en charge aujourd’hui. L’app iPhone, les widgets iPhone et la synchronisation des règles via CloudKit sont prévus ultérieurement.
- Ce projet n’est pas un serveur CalDAV et ne duplique pas la hiérarchie des comptes ou catégories d’Apple Calendar.
- Consultez [Documentation/PRODUCT.md](Documentation/PRODUCT.md) pour le contrat détaillé du produit et des données.

## Structure du dépôt

- `Source/` : sources Swift, configuration XcodeGen, tests et scripts de compilation.
- `Documentation/` : contrat produit, instructions d’installation et exemples JSON anonymes.
- `Releases/1.0.0/` : notes de version et somme de contrôle SHA-256 ; le DMG est distribué via GitHub Releases.

## Licence

Ce projet est publié sous [licence MIT](LICENSE).
