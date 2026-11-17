# Run: Aperçus du presse-papiers AppKite

## Run 1

- Head: `062fc3bd3e59d68cfb42a7928e69fcd61b8693a1`
- Left: Validation à l’exécution sous macOS 26. Xcode cible macOS 26, mais le seul hôte disponible pour ce run exécute macOS 27.2.1. Les changements restent non committés dans `feat/apercus-presse-papiers`. Le worktree original conserve le correctif d’audit.

| Task | Validation | Result |
| --- | --- | --- |
| 1.1 | Contrôles de base et montage isolé. | Le worktree est basé sur `main` avec la copie du correctif d’audit. Les tests utilisent un stockage et un presse-papiers dédiés. Xcode 27.2 a compilé le schéma, avec macOS 26 comme cible minimale. |
| 1.2 | Swift Testing sur PNG direct et archivé, orientation, transparence et archive après suppression de l’original. | Image et dimensions conservées. L’aperçu part de l’archive et le décodage est séparé de la publication de la recherche. |
| 2.1 | Swift Testing sur un PDF de deux pages et un DOCX synthétique archivé. | Première page du PDF vérifiée et page de contenu DOCX rendue par Quick Look sur macOS 27.2.1. |
| 2.2 | Swift Testing sur CSV, TSV, guillemets et valeurs tabulaires directement copiées. | Les lignes et cellules restent distinctes. Les champs entre guillemets gardent leur contenu. |
| 2.3 | Swift Testing sur dossier, sélection mixte et lien externe. | La mosaïque compte les éléments directs, conserve l’ordre de la sélection et laisse la cible des liens hors du rendu. |
| 3.1 | Swift Testing sur représentations directes, fichiers Finder et références distantes. | Les octets directs restent recollables et le fichier Finder garde son chemin de restitution. Les listes de lecture, alias et références externes sont écartés du lecteur. |
| 3.2 | Swift Testing sur MOV orienté, M4A avec pochette, WAV sans pochette et GIF. | L’image vidéo, la pochette, la forme d’onde réelle et le cycle GIF sont vérifiés sur macOS 27.2.1. |
| 4.1 | Swift Testing du lecteur et XCTest après suppression d’un WAV original et relance. | La lecture agit dans la carte, le bandeau reste ouvert et la réouverture remet le média à l’arrêt. Le test de changement de média vérifie que l’ancienne demande reste annulée. |
| 4.2 | Xcode BuildProject, `xcodebuild test-without-building`, deux rendus du bandeau, lint Swift strict et `git diff --check`. | **89 tests réussis**, dont 83 unitaires et d’intégration et 6 d’interface, zéro échec et zéro test ignoré. Les aperçus Xcode large et compacte se rendent. |

La mesure à l’écran sur macOS 27.2.1 utilise la vue SwiftUI, une base SwiftData temporaire de 10 000 cartes et un flux ScreenCaptureKit limité à la fenêtre de la sonde. Huit recherches chauffent la série, puis 100 recherches donnent chacune un échantillon. La mesure part de la mise à jour du champ et s’arrête à la première image complète du résultat attendu, datée par le serveur de fenêtres.

| Série | Échantillons valides | Médiane | p95 | Max |
| --- | ---: | ---: | ---: | ---: |
| Au repos | 100 | 87,28 ms | 95,68 ms | 104,77 ms |
| Avec demandes d’aperçus d’archives | 100 | 81,97 ms | 93,80 ms | 110,44 ms |

La série en charge relance 12 demandes d’aperçus PNG archivés par recherche avec deux travaux simultanés au maximum. Au moins un rendu d’archive a réellement abouti. La sonde et le journal agrégé sont conservés dans `build/validation/`. Le seuil à l’écran de 200 ms est respecté sur cet hôte.

## Reprise dans le dossier AppKite

- La branche `feat/apercus-presse-papiers` est ouverte dans le dépôt habituel, avec son projet `AppKite.xcodeproj`. Le dossier de travail supplémentaire a été retiré après comparaison des sources, des tests et des fichiers ajoutés.
- Le diff indépendant des corrections de l’audit est conservé dans la sauvegarde Git locale `bdd35fe0b6343306efa5b82f60245f9f3df1894c` de la branche `fix/qualite-historique-presse-papiers`, avec le rapport d’audit. Les aperçus s’appuient sur ces corrections.
- Compilation du schéma `AppKite` et suite complète via `xcodebuild` depuis le dossier habituel. Sous macOS 27.2.1, **89 tests réussis**, zéro échec et zéro test ignoré. Le rapport Xcode signale des avertissements sur le thread principal et les priorités de threads pendant les tests.

## Périmètre de validation approuvé

Le 16 novembre 2026, Yanis a accepté de poursuivre la revue des aperçus sur les résultats de macOS 27.2.1 et de retenir la compatibilité d’exécution sous macOS 26 par hypothèse. La cible minimale reste macOS 26.0. Les résultats d’exécution de ce rapport portent sur macOS 27.2.1.

## Run 2 · Corrections de la revue

- Head: `062fc3bd3e59d68cfb42a7928e69fcd61b8693a1`
- Left: Intégration préalable des corrections d’audit, puis commit et PR des aperçus après validation Git.
- Branche `feat/apercus-presse-papiers` avec les modifications locales, dans le projet `AppKite.xcodeproj` habituel.
- Les tests ciblés ont reproduit les trois défauts avant correction. La suite complète après correction compte **93 tests réussis**, dont **8 d’interface**, zéro échec et zéro test ignoré sur macOS 27.2.1.

| Task | Validation | Result |
| --- | --- | --- |
| 1.1 | Compilation depuis le projet AppKite habituel, parcours XCTest avec historique et presse-papiers isolés. | L’environnement de référence reste macOS 27.2.1. |
| 1.2 | Test PNG direct et fichier archivé après retrait de l’original. | L’image conserve ses proportions et ses dimensions. |
| 2.1 | Tests de la première page du PDF et des miniatures DOCX et ODT. | Quick Look rend une page de contenu pour les deux documents archivés. |
| 2.2 | Tests des fichiers CSV et TSV et de la représentation tabulaire directe. | Les valeurs entre guillemets restent dans leur cellule. |
| 2.3 | Tests de dossiers, sélections et liens. | Les miniatures et le compteur correspondent aux éléments archivés. |
| 3.1 | Régression avec un MOV illisible et un PNG valide dans le même élément. | AppKite affiche le PNG de l’archive. |
| 3.2 | Régression sur le GIF animé précédé d’un PNG, puis sur un GIF illisible. Tests de vignette vidéo, pochette et forme d’onde. | Le GIF animé fournit le contrôle de lecture. Le PNG sert de repli lorsque le GIF est illisible. |
| 4.1 | Parcours XCTest WAV, GIF et MOV après retrait des originaux et relance. | Le GIF et le MOV archivés se lisent jusqu’au bout dans leur carte. Le parcours audio confirme l’arrêt à la fermeture. |
| 4.2 | `BuildProject`, suite Xcode complète, `RenderPreview` large et compact, lint Swift strict et `git diff --check`. | Compilation et deux rendus réussis depuis le projet AppKite. 93 tests réussis. |

Les deux captures se trouvent dans `build/validation/revue-2-large.png` et `build/validation/revue-2-compact.png`. Le rapport Xcode contient des avertissements d’exécution sur le thread principal et les priorités de threads. Les mesures de latence figurent au Run 1.
