---
objective: "Livrer l’historique local qui permet de retrouver et de recoller les neuf familles de copies du presse-papiers sur macOS 26 et 27."
status: implemented
---

# Plan: Historique du presse-papiers

Source [Spec V1 validée](./spec.md) et [brainstorm approuvé](./brainstorm.md).

## Phases

| # | Phase | File | Depends on |
| --- | --- | --- | --- |
| 1 | Copier, ouvrir et recoller du texte | [phase-1.md](./phase-1.md) | none |
| 2 | Gérer les cartes, les collections et la collecte | [phase-2.md](./phase-2.md) | 1 |
| 3 | Restituer les formats et gérer les archives sur disque | [phase-3.md](./phase-3.md) | 1, 2 |
| 4 | Rechercher, filtrer et mesurer | [phase-4.md](./phase-4.md) | 1, 2, 3 |

## External sources

| URL | What it settled |
| --- | --- |
| [Apple · Changements du presse-papiers](https://developer.apple.com/documentation/appkit/nspasteboard/changecount), [Apple · Accès au presse-papiers](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-9k4t4) | Le compteur signale un changement de propriétaire sans l’identifier. Le SDK expose l’état d’accès dès macOS 15.4. |
| [Apple · Éléments du presse-papiers](https://developer.apple.com/documentation/appkit/nspasteboarditem/types), [Convention des marqueurs du presse-papiers](https://nspasteboard.org/) | Un élément peut fournir plusieurs représentations. La confidentialité et l’origine peuvent être déclarées par le producteur. L’origine déclarée est facultative et non authentifiée. |
| [Apple · Raccourci Option et Majuscule](https://developer.apple.com/forums/thread/763878), [Apple · Position du pointeur](https://developer.apple.com/documentation/appkit/nsevent/mouselocation), [Apple · Zone visible](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe) | Le SDK public HIToolbox expose l’enregistrement global et le conflit de réservation. AppKit fournit les coordonnées et la zone visible de l’écran. |
| [Apple · Activation coopérative](https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation), [Apple · Envoi à un processus](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:)), [Apple · Autorisation d’envoi](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess()) | L’activation est une demande. L’envoi à un PID a une autorisation distincte et ne confirme pas l’insertion dans l’app destinataire. |
| [Apple · Stockage SwiftData local](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices#Disable-automatic-sync-in-apps-already-using-CloudKit), [Apple · Contexte de modèle](https://developer.apple.com/documentation/swiftdata/modelcontext) | Une configuration locale explicite désactive la synchronisation. Les écritures du contexte n’englobent pas les fichiers d’archives. |
| [Apple · Système de fichiers APFS](https://developer.apple.com/documentation/foundation/about-apple-file-system), [Apple · Capacité du volume](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeavailablecapacityforimportantusage) | La taille d’un fichier, les blocs partagés d’un clone et l’espace récupérable sont des mesures différentes. La capacité du volume est un signal à vérifier avant et après une opération. |
| [Apple · Reconnaissance de texte](https://developer.apple.com/documentation/vision/recognizetextrequest), [Apple · Texte d’un PDF](https://developer.apple.com/documentation/pdfkit/pdfdocument/string) | Vision reconnaît le texte des images localement. PDFKit expose le texte déjà présent dans le document. |

## Impact

| Category | Verdict and evidence | Handled in |
| --- | --- | --- |
| Runtime | Hôte Apple Silicon sous macOS 27.2, Xcode 27.2 et SDK 27.2 observés. Une sonde éphémère a enregistré puis libéré `⇧⌥V` avec deux statuts `0`. La livraison de l’événement, le collage et la confidentialité restent à vérifier en interface. L’exécution sous macOS 26 reste à établir sur un hôte ou une VM compatible. | 1, 4 |
| Runtime | Le SDK public ne donne pas l’identité authentifiée du producteur d’un changement de presse-papiers. La fiabilité de l’attribution sur des copies ordinaires reste à mesurer. Les opérations sous pression disque et la fidélité des formats dépendent des fichiers et apps de destination. | 1, 2, 3 |
| Regression | Risque moyen sur le menu et le focus. Les suites existantes contrôlent `LSUIElement`, une seule icône et le cycle quitter puis relancer. Le test d’interface fixe aussi un compte d’actions devenu incompatible avec la spec. Les assertions de socle servent de garde-fou dès la première phase. | 1 |
| Architecture | La scène actuelle compose uniquement l’action Quitter. Le projet Xcode inclut déjà les trois dossiers de cibles. `App` assemble la feature `ClipboardHistory`, dont les adaptateurs restent dans la cible existante. Le projet active actuellement l’isolation MainActor par défaut. Les tâches de stockage, d’archivage et de recherche ont une isolation explicite hors de l’acteur d’interface. | 1, 3, 4 |
| Documentation | Les phases sont regroupées avec la spec approuvée. Le `.gitignore` local existant est un livrable du commit et de la PR de la feature, soumis aux validations VCS. | 4 |

## Rules

| Rule | Why it applies |
| --- | --- |
| [Architecture](../../../memory/architecture.md) et [stockage](../../../memory/database.md) | Les vues ne connaissent ni les modèles SwiftData ni les fichiers du stockage. L’adaptateur persiste les métadonnées localement et stocke les gros contenus en fichiers. |
| [Desktop](../../../memory/desktop.md) | Limiter l’intégration aux API publiques Apple. Vérifier l’accès à la lecture et à l’envoi de touches séparément sur macOS 26 et 27. |
| [Assert](../../../memory/coding-assertions.md) et [tests](../../../memory/testing.md) | Exécuter la compilation, les suites prévues et les Previews via le MCP Xcode officiel. Obtenir un accord explicite sur tout écart au contrat avant de l’accepter. |
| [VCS](../../../memory/vcs.md) | Après l’assert et la revue, préparer le commit et la PR vers `main` avec le `.gitignore` local dans le périmètre. La préparation du build validé suit la règle de numérotation du projet. |

## Decisions

| Decision | Why |
| --- | --- |
| Conserver l’ordre des éléments et leurs représentations reconnues | Une carte doit pouvoir restaurer un groupe Finder, du contenu mixte ou les formats de tableur avec leur repli. Le rendu et la recherche utilisent des résumés distincts des données à recoller. |
| Distinguer provenance déclarée et provenance inconnue | La fenêtre au premier plan ne prouve pas l’origine de la copie. La validation d’attribution sur des apps courantes précède l’acceptation des exclusions et des filtres. |
| Sérialiser les mutations du stockage local | SwiftData et les archives sur disque exigent une publication cohérente, la reprise des opérations interrompues et des protections stables pendant le nettoyage. |
| Indexer le texte et les filtres indépendamment des contenus à coller | La recherche doit respecter le budget de latence pendant les extractions OCR et les copies de gros fichiers. |
