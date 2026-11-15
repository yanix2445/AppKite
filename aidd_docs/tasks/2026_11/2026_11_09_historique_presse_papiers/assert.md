# Assert — Historique du presse-papiers

## Round 1

- Date de vérification : 13 novembre 2026.
- HEAD : `385c6f5`, branche `feat/historique-presse-papiers`, avec les changements locaux de la fonctionnalité.
- Environnement : macOS 27.2.1, Xcode 27.2.
- Verdict : **FAIL**.

| Vérification | Résultat | Échec |
| --- | --- | --- |
| MCP Xcode `BuildProject` · schéma AppKite | 0 | |
| MCP Xcode `RunAllTests` · schéma AppKite | 1 | 46 tests réussis sur 48. Le lanceur XCTest s’est arrêté dans `XCTCrashLogTracker.waitForPendingCrashlogs()`. Le test du raccourci global n’a pas trouvé le champ de recherche. |
| MCP Xcode `RenderPreview` · bandeau sombre, bandeau compact et réglages | 0 | |

L’exécution des tests d’interface a déclenché la demande macOS « Enable UI Automation ». Les trois aperçus ont été inspectés.

## Round 2

- Date de vérification : 13 novembre 2026.
- HEAD : `385c6f5`, avec le même code local qu’au premier passage.
- Environnement : macOS 27.2.1, Xcode 27.2, exécution séquentielle.
- Verdict : **PASS** pour la suite automatisée sur ce Mac.

| Vérification | Résultat | Échec |
| --- | --- | --- |
| MCP Xcode `BuildProject` · schéma AppKite | 0, vérifié au premier passage | |
| `xcodebuild test` · schéma AppKite, destination macOS arm64, `-parallel-testing-enabled NO` | 0 · 48 réussites, dont 5 tests d’interface | |
| MCP Xcode `RenderPreview` · bandeau sombre, bandeau compact et réglages | 0, vérifié au premier passage | |

Le test du raccourci depuis Finder et le test du menu vérifient que le champ de recherche est visible et reçoit la saisie au clavier. Les deux réussissent à la relance. Le premier échec du raccourci reste consigné car sa cause n’a pas été isolée.

Les validations sur macOS 26, du refus réel de lecture, de Handoff et du nettoyage automatique sur APFS restent ouvertes.

## Round 3

- Date de vérification : 13 novembre 2026.
- HEAD : `385c6f5`, avec les changements locaux de la fonctionnalité.
- Environnement : macOS 27.2.1, Xcode 27.2.
- Résultat : validation du stockage et des tests unitaires. Validation d’interface partielle.

| Vérification | Résultat |
| --- | --- |
| Compilation Xcode et tests unitaires finaux | 44 tests réussis, dont le refus pendant la lecture et la persistance d’une copie distante avec sa restitution. |
| Suite complète avant les derniers ajustements | 49 tests réussis, dont 5 tests d’interface. La relance complète suivante a expiré en attendant l’autorisation macOS « Enable UI Automation ». |
| Volume APFS isolé de 160 Mio | Un clone partagé représente 0 octet récupérable. Un fichier indépendant de 9 Mio représente 9 Mio récupérables. Une copie trop grande conserve les cinq cartes. Une copie de 12 Mio entraîne la suppression d’une seule carte ordinaire éligible. Les cartes épinglée, classée, réutilisée récemment et à blocs partagés restent présentes. La nouvelle archive est relue après réouverture. |
| Refus macOS réel | Une app isolée avec l’option développeur a renvoyé `.alwaysAllow` avant et après la lecture. Le refus et la reprise sont vérifiés par simulation. |
| Presse-papiers universel | Le marqueur distant est couvert par les tests. Le transfert entre deux appareils physiques reste à vérifier. |
| macOS 26 | Compatibilité retenue par hypothèse à la demande de Yanis. Essai sur appareil indisponible. |

## Round 4

- Date de vérification : 15 novembre 2026.
- HEAD : `385c6f5`, avec les changements locaux de la fonctionnalité.
- Environnement : macOS 27.2.1, Xcode 27.2.
- Verdict : **PASS** pour la suite automatisée sur ce Mac.

| Vérification | Résultat |
| --- | --- |
| `xcodebuild test` · schéma AppKite, destination macOS arm64, `-parallel-testing-enabled NO` | 0 · 49 réussites, dont 5 tests d’interface, aucun test ignoré. |
| `git diff --check` et `swift-format lint --strict` sur les fichiers Swift de la dernière modification | 0. |

La confirmation de l’autorisation XCTest a permis de relancer la suite avec le dernier code. Les cas de refus et de copie distante sont testés par simulation. Le refus système en conditions réelles et le transfert avec un second appareil physique restent à vérifier.

## Round 5

- Date de vérification 15 novembre 2026.
- Branche `feat/historique-presse-papiers` à `385c6f5`, avec les corrections locales de la revue.
- Environnement macOS 27.2.1, Xcode 27.2, Apple Silicon.
- Verdict **PASS** pour la compilation et les tests via `xcodebuild`. L’assert MCP reste incomplet.

| Vérification | Résultat |
| --- | --- |
| Test du doublon Finder avec répertoire de préparation indisponible | Avant correction, l’archivage échoue dans `staging`. Après correction, la recopie actualise l’origine et la date de la même carte et conserve son épingle et ses données. |
| `xcodebuild test` · AppKite, macOS arm64, séquentiel | 0. Le résumé `xcresulttool` confirme 55 tests réussis, dont 5 d’interface, avec zéro échec et zéro test ignoré. |
| Volume APFS de 160 Mio, environ 6,2 Mio libres | Le doublon de 9 Mio, venant d’un autre volume, remonte la carte existante. Le nouveau fichier de 12 Mio reçoit l’erreur de capacité. La réouverture conserve les deux cartes, le contenu et l’épingle. `staging` est vide. Après libération d’espace, le fichier de 12 Mio est archivé. |
| Collecte pendant un archivage suspendu | Deux copies supplémentaires sont sondées pendant l’attente, puis enregistrées en ordre avec leurs dates de capture. |
| Repli CSV | Les tests et une sonde AppKit sur presse-papiers privé vérifient la représentation TSV, la préservation du CSV original, les cellules vides, les champs entre guillemets, les sauts de ligne et l’utilisation des représentations existantes. |
| `git diff --check` et `swift-format lint --strict` | 0 sur les changements suivis et les dix fichiers Swift de la correction. |
| `BuildProject`, `RunAllTests`, `RenderPreview` via MCP Xcode | Le pont a demandé une autorisation pour cette session et l’ouverture de l’espace de travail a expiré. Compilation et tests vérifiés en CLI. Aperçus du dernier état à relancer. |

L’essai APFS démontre la préservation de l’historique. L’éviction automatique est suspendue lorsqu’une archive définitive ne peut être produite avec la place disponible. Ce point reste ouvert dans la [phase 3](phase-3.md#état-de-la-validation).

## Round 6

- Date de vérification 15 novembre 2026.
- Branche `feat/historique-presse-papiers` à `385c6f5`, avec le nouveau nettoyage APFS.
- Environnement macOS 27.2.1, Xcode 27.2, Apple Silicon.
- Verdict **PASS**. Le client Codex signé, déjà autorisé par Xcode, a exécuté les trois vérifications MCP sur l’état final.

| Vérification | Résultat |
| --- | --- |
| MCP Xcode `BuildProject` · AppKite | 0. Compilation de l’application et des cibles de test réussie. |
| MCP Xcode `RunAllTests` · AppKite | 0. 55 tests réussis, dont 5 d’interface, zéro échec et zéro test ignoré. |
| MCP Xcode `RenderPreview` · bandeau Liquid Glass, bandeau compact et réglages | 0. Trois rendus produits et vérifiés visuellement. |
| Préallocation et éviction sur un volume APFS isolé de 160 Mio | La réserve initiale occupait 16 Mio de blocs. Avec environ 6,9 Mio libres, le doublon de 9 Mio a remonté sa carte sans suppression. La copie de 30 Mio a été refusée. Celle de 12 Mio a d’abord été refusée faute de candidats suffisants après préparation. Après rétablissement de candidats ordinaires, la même copie a remplacé la carte éligible la moins récemment utilisée. Les cartes épinglée, classée, réutilisée et à blocs partagés ont été retrouvées avec leurs octets après réouverture. Une réserve d’environ 9,8 Mio a été reconstituée sous pression. |
| Interruption du processus sur deux images APFS isolées de 128 Mio | La sonde temporaire a arrêté le processus juste avant ou juste après la sauvegarde SwiftData. Avant, la réouverture a conservé les anciennes cartes et retiré l’archive orpheline. Après, elle a conservé la nouvelle carte et la carte épinglée et retiré les anciens fichiers orphelins. Les contenus conservés ont été comparés octet pour octet aux sources. |
| `git diff --check` et `swift-format lint --strict` | 0 sur les fichiers modifiés dans cette passe. |

La récupération dépend de la place effectivement libérée par la réserve et des blocs récupérables des cartes ordinaires. Si la nouvelle copie ne peut pas être écrite entièrement avant la sauvegarde, la récupération est abandonnée. Les vérifications physiques de Handoff et de refus d’accès réel gardent les limites consignées aux passages précédents.

## Round 7

- Date de vérification 15 novembre 2026.
- Branche `feat/historique-presse-papiers` à `385c6f5`, avec le code de la fonctionnalité validé au Round 6.
- Environnement macOS 27.2.1, Apple Silicon, un écran actif, un iPhone pour le parcours Handoff.
- Résultat **partiel**. Handoff est vérifié sur deux appareils physiques. Le refus réel de lecture reste sans reproduction et la mesure sur le code courant s’arrête avant l’affichage.

| Vérification | Résultat |
| --- | --- |
| Handoff réel · Notes sur iPhone vers macOS | Yanis a confirmé le collage dans TextEdit. Une seconde copie est parvenue à `PasteboardClient` avec `isRemote` à `true` et sans origine locale. Le texte a été archivé et relu après réouverture, puis restitué à l’identique par `PasteClipboardEntry` avec un presse-papiers de test. |
| Raccourci occupé | Le conflit exclusif via HIToolbox a laissé l’ancien raccourci actif et persisté. |
| Géométrie du bandeau et refus simulé | Le panneau se place au bord inférieur de l’écran du pointeur, au-dessus du Dock. Sous `.alwaysDeny` injecté, le bandeau affiche le message et le bouton de réglages. La carte antérieure reste disponible dans l’état du bandeau. |
| Refus macOS réel | Deux sondes isolées détectent l’option développeur, puis obtiennent `.alwaysAllow` avant et après la lecture. La recherche des Réglages Système n’affiche aucun contrôle correspondant. |
| Recherche sur 10 000 cartes | p95 **44,03 ms** au repos et **47,11 ms** pendant 226 opérations d’archivage concurrentes. Les 200 résultats étaient conformes aux attentes. La mesure s’arrête à la disponibilité du premier lot pour la vue SwiftUI. |

Le [Round 6](#round-6) conserve les résultats de compilation, des 55 tests Xcode et des trois aperçus. Les éléments matériels à valider sont détaillés dans les [notes de la phase 1](phase-1-validation.md) et la [phase 4](phase-4.md#état-de-la-validation).

## Round 8

- Date de vérification 15 novembre 2026.
- Environnement macOS 27.2.1 et Xcode 27.2, Apple Silicon.
- Résultat **PASS** pour la latence à l’écran. Le refus d’accès système demeure ouvert.

| Vérification | Résultat |
| --- | --- |
| 10 000 cartes, 100 recherches au repos | Médiane 74,50 ms, p95 **90,50 ms**, maximum 102,69 ms. |
| 10 000 cartes initiales, 100 recherches avec 497 archivages de 8 Mio | Médiane 87,46 ms, p95 **106,16 ms**, maximum 110,53 ms. |
| Refus réel d’accès au presse-papiers | Les notes de version de macOS 27.2 confirment le retrait de l’option développeur utilisée par les sondes (186955507). L’environnement courant rapporte toujours `.alwaysAllow` et ne présente aucun réglage correspondant. Le contrôle par simulation reste documenté au Round 7. [Notes Apple](https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes). |

La mesure part de la mise à jour de la liaison du champ et utilise l’horodatage de la première image complète qui montre le résultat attendu dans la fenêtre visible. Le sélecteur macOS a limité le flux à la fenêtre de test. La sonde a traité les pixels en mémoire et conservé les temps agrégés. Le premier lancement a quitté à la sélection de la fenêtre à cause d’une hypothèse d’isolation sur le rappel ScreenCaptureKit. Le banc corrigé a terminé les deux séries. [Méthode et limites](phase-4.md#état-de-la-validation).

## Round 9

- Date de vérification 15 novembre 2026.
- Branche `feat/historique-presse-papiers` à `385c6f5`, avec l’implémentation locale.
- Environnement macOS 27.2.1, Xcode 27.2, Apple Silicon.
- Verdict **PASS** pour la validation de clôture. Yanis a validé le report du scénario de refus réel d’accès le 15 novembre 2026.

| Vérification | Résultat |
| --- | --- |
| MCP Xcode `BuildProject` · AppKite, cibles de tests incluses | Compilation réussie, zéro erreur. |
| MCP Xcode `RunAllTests` · AppKite | **55 tests réussis**, dont 5 d’interface, zéro échec et zéro test ignoré. |
| MCP Xcode `RenderPreview` | Trois aperçus produits sans erreur, bandeau Liquid Glass, bandeau compact et réglages. |
| `git diff --check` et `swift-format lint --strict` | Contrôles réussis sur le diff suivi et les sources Swift des suites et de la feature. |

Les preuves [APFS](#round-6), [Handoff sur deux appareils](#round-7) et [latence à l’écran](#round-8) restent rattachées à cette version locale. Le refus est exercé par simulation et la compatibilité d’exécution sous macOS 26 est retenue par hypothèse, avec les accords consignés dans les phases concernées.

## Round 10

- 15 novembre 2026, branche locale `feat/historique-presse-papiers` à `385c6f5` avec les corrections de la revue.
- macOS 27.2.1, Xcode 27.2, Apple Silicon.
- Verdict **PASS**. Les scénarios de la revue ont été rejoués sur le code corrigé.

| Vérification | Résultat |
| --- | --- |
| MCP Xcode `BuildProject` et `RunAllTests` | Compilation réussie, **62 résultats réussis**, dont 57 unitaires ou d’intégration et 5 d’interface. Zéro échec et zéro résultat ignoré. |
| MCP Xcode `RenderPreview` | Quatre captures produites sans erreur. Bandeau Liquid Glass, bandeau compact, bandeau sur le bureau et réglages. |
| ACL de suppression | Le fichier archivé refusait la suppression standard. AppKite a supprimé la carte et son archive. Le fichier original est resté lisible et protégé. Une autre carte est restée accessible après relance. |
| Orphelins protégés et ouverture concurrente | Les archives valides restent accessibles malgré deux orphelins protégés dans `staging` et `archives`. Les orphelins sont supprimés à la réouverture après retrait de la protection. Un deuxième processus reçoit `storageInUse` et laisse la copie en préparation intacte. Après l’arrêt forcé du premier processus, la relance récupère la carte et nettoie le dossier de préparation. |
| Volume APFS isolé de 160 Mio | La copie trop grande préserve les cinq cartes. La copie de 12 Mio remplace uniquement la carte éligible la moins récemment utilisée. Les cartes épinglée, classée, réutilisée récemment et à blocs partagés sont relues octet pour octet après réouverture. La réserve physique est rétablie à 10 280 960 octets sous pression. |
| Interruptions sur deux images APFS de 128 Mio | Une sonde s’arrête juste avant ou juste après la sauvegarde SwiftData. La relance conserve les cartes et les fichiers attendus dans chaque cas et supprime les archives orphelines. |
| Rejets d’archivage | Une copie refusée faute d’espace ou une sélection Finder invalide reste signalée après une copie réussie. La prochaine sélection invalide déclenche un nouveau message après fermeture. |
| Pagination des vignettes | Des images retrouvent leur vignette après 48 et après 144 cartes sans vignette. Les résultats déjà traités ne sont pas relus lors de la page suivante. |
| Cinq parcours XCTest isolés | Ouverture par raccourci et menu, relance, recherche par type et gestion des collections. Chaque parcours vérifie la création de sa base temporaire et la supprime après exécution. |
| Contrôles statiques | `swift-format lint --strict` et vérification des espaces dans les fichiers suivis et non suivis réussis. |

Les régressions ciblées échouent avec les comportements antérieurs. Le refus d’accès est couvert par simulation. La validation macOS 26 repose sur l’hypothèse acceptée et les mesures de latence sont consignées au [Round 8](#round-8).
