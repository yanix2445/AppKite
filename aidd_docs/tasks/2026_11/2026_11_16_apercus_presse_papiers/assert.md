# Assert des aperçus et de la sélection multiple

## Round 1

- Date du 17 novembre 2026. Branche `feat/apercus-presse-papiers` à `96ff00c` avec les modifications locales.
- Verdict **FAIL** au démarrage des tests d’interface.

| Vérification | Sortie | Résultat |
| --- | --- | --- |
| Xcode `BuildProject` | 0 | Schéma AppKite et cibles de tests compilés. |
| Xcode `RunAllTests` et lecture du résultat brut | 4 | `Timed out while enabling automation mode.` |
| Xcode `RenderPreview` | — | Étape reportée après la relance de la suite. |

## Round 2

- Même candidat avec les aperçus et la sélection multiple, y compris ⌘A sur les résultats au-delà de la première page.
- Environnement Apple Silicon sous macOS 27.2.1 et Xcode 27.2.
- Verdict **PASS** pour les assertions du projet.

| Vérification | Sortie | Résultat |
| --- | --- | --- |
| Xcode `BuildProject` | 0 | Compilation du candidat réussie au Round 1, sources identiques au Round 2. |
| Xcode `RunAllTests` et lecture avec `xcresulttool` | 0 | 97 tests réussis, dont 10 d’interface. Les tests paramétrés portent le nombre d’exécutions à 100. Zéro échec et zéro test ignoré. |
| Xcode `RenderPreview` | 0 | Bandeau Liquid Glass et bandeau compact rendus et vérifiés. |
| `git diff --check` et `swift-format lint --strict` | 0 | Contrôles réussis sur le diff et 29 fichiers Swift. |
| Sonde à l’écran sur 10 000 cartes | 0 | p95 de 105,81 ms au repos et de 107,42 ms avec des demandes de rendu, pour 100 mesures dans chaque série. Seuil attendu inférieur à 200 ms. |

La compilation et les tests utilisent le projet habituel. La relance des tests a maintenu l’écran actif pendant leur exécution. Xcode signale des avertissements existants de thread principal et d’inversion de priorité. La compatibilité d’exécution sous macOS 26 repose toujours sur l’hypothèse acceptée dans le [rapport précédent](run.md#périmètre-de-validation-approuvé).

Les preuves locales de ce cycle se trouvent dans `build/validation/assert-apercus.oSrJsOLN/`.

## Round 3

- Date du 17 novembre 2026. Branche `feat/apercus-presse-papiers` à `96ff00c` avec les corrections locales de la revue.
- Environnement Apple Silicon, macOS 27.2.1, Xcode 27.2.
- Verdict **PASS** pour le candidat corrigé.

| Vérification | Sortie | Résultat |
| --- | --- | --- |
| Xcode `BuildProject` | 0 | AppKite et les cibles de tests compilés. |
| Xcode `RunAllTests` et lecture avec `xcresulttool` | 0 | 103 tests réussis, dont 10 d’interface, zéro échec et zéro test ignoré. 107 exécutions avec les tests paramétrés. |
| Xcode `RenderPreview` | 0 | Bandeau Liquid Glass et bandeau compact rendus. |
| `git diff --check` et `swift-format lint --strict` | 0 | Contrôles réussis sur le diff et les sources Swift touchées. |
| Sonde à l’écran sur 10 000 cartes | 0 | p95 de 111,51 ms au repos et de 112,14 ms avec des demandes de rendu, sur 100 mesures par série. Seuil attendu inférieur à 200 ms. |

Les régressions testées concernent un lot trop volumineux avec une restitution préalable à préserver, ⌘A avant l’ouverture du stockage et pendant une recherche, le repli sur une représentation PNG et les coupures de lignes tabulaires en UTF-8 et UTF-16. Les preuves locales se trouvent dans `build/validation/assert-apercus-final.Ix8kAIXP/`.
