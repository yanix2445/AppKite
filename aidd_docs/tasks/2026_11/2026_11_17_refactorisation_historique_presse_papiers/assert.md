# Assert: Séparer les responsabilités de l’historique

## Round 1

- Head: `3d55422`
- Uncommitted changes: yes
- Verdict: PASS
- Branche `refactor/responsabilites-historique`. Vérifications du 18 novembre 2026 sur Apple Silicon, macOS 27.2.1 et Xcode 27.2 (27B52).

| Check | Exit | Failure |
| --- | ---: | --- |
| `BuildProject` avec `buildForTesting: true` | 0 | |
| `RunAllTests` et lecture du résultat avec `xcresulttool` | 0 | |
| `RenderPreview` · bandeau Liquid Glass | 0 | |
| `RenderPreview` · bandeau compact | 0 | |
| `RenderPreview` · réglages du presse-papiers | 0 | |
| `git diff HEAD --check` et contrôle des fichiers non suivis | 0 | |
| `xcrun swift-format lint --strict` · 21 fichiers Swift, indentation à quatre espaces | 0 | |
| Sonde optimisée de recherche à l’écran, seuil p95 strictement inférieur à 200 ms | 0 | |

Xcode rapporte **119 tests réussis**, dont **10 d’interface**, pour **124 exécutions** avec les cas paramétrés. Aucun échec, test ignoré ou test non exécuté. Le scénario de relance de l’indexation et les parcours audio, GIF et vidéo font partie de cette même passe.

La recherche atteint **92,31 ms au p95 au repos** et **94,10 ms pendant le rendu des aperçus**, sur 10 000 cartes et 100 mesures par série. La sonde a présenté les résultats à l’écran et vérifié que des rendus d’archives se sont terminés dans la série en charge.

Les avertissements d’exécution déjà observés sur le thread principal et les priorités de threads restent visibles dans le résultat Xcode. La validation en exécution porte sur macOS 27.2.1. Pour macOS 26, le projet conserve le périmètre approuvé dans la [spec](spec.md).

Les résultats bruts, les captures et les mesures sont conservés dans `build/validation/refactor-historique.i4la7aik/assert-responsabilites.igydcvo_/`.

## Round 2

- Head: `3d55422`
- Uncommitted changes: yes
- Verdict: PASS
- Branche `refactor/responsabilites-historique`. Vérifications du 18 novembre 2026 sur Apple Silicon, macOS 27.2.1 et Xcode 27.2 (27B52), après la correction du démarrage lorsque la lecture des collections échoue.

| Check | Exit | Failure |
| --- | --- | --- |
| `BuildProject` avec `buildForTesting: true` | 0 | |
| `RunAllTests` et vérification des suites avec `xcresulttool` | 0 | |
| `RenderPreview` · bandeau Liquid Glass | 0 | |
| `RenderPreview` · bandeau compact | 0 | |
| `RenderPreview` · réglages du presse-papiers | 0 | |
| `git diff HEAD --check` et contrôle des fichiers non suivis | 0 | |
| `xcrun swift-format lint --strict` · 21 fichiers Swift, indentation à quatre espaces | 0 | |
| Compilation optimisée et exécution de la sonde à l’écran, seuil p95 strictement inférieur à 200 ms | 0 | |

Xcode rapporte **120 tests réussis**, dont **10 d’interface**, pour **125 exécutions** avec les cas paramétrés. Aucun échec, test ignoré ou test non exécuté. Le test `archivesRemainAccessibleWhenInitialCollectionsFail()` confirme la recherche puis la restitution du fichier archivé lorsque le stockage s’ouvre et que la lecture des collections échoue.

Les trois captures sont identiques à celles du premier assert. Sur 10 000 cartes et 100 recherches par série, le p95 à l’écran atteint **99,09 ms au repos** et **90,62 ms pendant le rendu des aperçus**. La sonde confirme que des rendus d’archives se terminent dans la série en charge.

Xcode signale 10 avertissements de thread principal et 2 de priorité de thread, les mêmes catégories qu’au premier assert. L’exécution a été vérifiée sous macOS 27.2.1. La compatibilité avec macOS 26 reste l’hypothèse approuvée dans la [spec](spec.md).

Les preuves, captures et empreintes du candidat sont conservées dans `build/validation/refactor-historique.i4la7aik/assert-collections.Zfok4l5c/`.
