---
status: done
---

# Instruction: Rechercher, filtrer et mesurer

## Architecture projection

```txt
.
├── AppKite/
│   └── Features/
│       └── ClipboardHistory/
│           ├── UseCases/
│           │   └── SearchClipboardHistory.swift ✅
│           ├── Infrastructure/
│           │   ├── ClipboardHistoryModels.swift
│           │   ├── ClipboardSearchIndex.swift ✅
│           │   ├── ClipboardTextExtractor.swift ✅
│           │   └── SwiftDataClipboardHistoryStore.swift
│           └── UI/
│               ├── ClipboardHistoryState.swift
│               └── ClipboardHistoryView.swift
├── AppKiteTests/
│   └── ClipboardHistory/
│       └── ClipboardSearchTests.swift ✅
└── AppKiteUITests/
    └── ClipboardHistoryUITests.swift
```

Les fichiers sans symbole sont introduits dans les phases précédentes et complétés ici.

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Charger 10 000 entrées mixtes et une série de requêtes connues | Les entrées, sources et textes attendus sont identifiés dans un stockage isolé | system |
| Happy path | Chercher un mot présent dans une image ordinaire, une capture, un PDF texte ou un PDF scanné | Les cartes correspondantes apparaissent une fois le texte extrait | system |
| Edge case | Chercher un mot présent seulement dans une zone numérisée d’une page PDF qui contient aussi du texte sélectionnable | Le mot retrouve le PDF hybride | system |
| Happy path | Croiser le filtre Image et un filtre par app, avec puis sans texte | Seules les cartes répondant aux filtres et à la recherche éventuelle apparaissent | system |
| Edge case | Chercher le nom d’un dossier puis un mot présent uniquement dans un PDF imbriqué | Le nom retrouve le dossier. Le texte du PDF imbriqué ne fait pas apparaître la carte du dossier | system |
| Edge case | Épingler une carte qui ne correspond pas à la recherche et refaire une copie identique depuis une autre source | L’épingle est filtrée. L’origine la plus récente gouverne le filtre d’app | system |
| Edge case | Supprimer une carte pendant l’indexation ou changer rapidement de requête | Une carte supprimée ou un résultat obsolète ne réapparaît pas | system |
| Edge case | Mesurer de la saisie à l’affichage des premiers résultats pendant l’indexation ou l’archivage | Le p95 est inférieur à 200 ms sur 10 000 entrées et la métrique est relevée avec la charge observée | system |
| Teardown | Supprimer le jeu de référence et fermer le stockage de test | Les index et archives de test sont retirés | system |

## Wireframe

```txt
┌────────────────────────────────────────────────────────────┐
│ (1) Recherche · filtre type · filtre app · collections    │
├────────────────────────────────────────────────────────────┤
│ (2) Épingles correspondantes [carte] [carte]                │
│ (3) Résultats               [carte] [carte] [carte] …       │
└────────────────────────────────────────────────────────────┘
```

1. Recherche, filtres combinables et accès aux collections.
2. Épingles qui satisfont les critères actifs.
3. Cartes correspondantes avec aperçus et sélection.

## Tasks to do

### `1)` Rendre recherchables les contenus admissibles

> Extraire du texte localement et garder des résultats à jour.

1. Indexer le texte copié, les URL, les valeurs de cellules et les noms de fichiers et de dossiers. Pour les PDF copiés directement, combiner le texte sélectionnable extrait via PDFKit avec l’OCR du rendu des pages numérisées ou hybrides. Utiliser Vision pour toutes les images copiées. Indexer un dossier par son nom, sans parcourir son contenu pour l’index.
2. Ordonner le travail d’extraction hors de l’acteur d’interface avec une concurrence bornée. Reprendre après relance et interrompre l’extraction devenue inutile. Éliminer les résultats d’une carte supprimée et mettre à jour les métadonnées à la recopie.
3. Interroger les métadonnées et l’index sans charger les contenus volumineux. Vérifier les correspondances sur des mots, URL, valeurs de cellules et noms de fichiers réels.

### `2)` Appliquer recherche et filtres au bandeau

> Donner la même sélection aux cartes affichées et aux actions au clavier.

1. Ajouter la recherche et les filtres par type et par app source. Combiner les filtres même sans requête et appliquer les critères à la section des épingles.
2. Annuler les requêtes périmées et borner le nombre de cartes et d’aperçus chargés pour le premier écran. Mettre à jour la sélection avec les résultats affichés et vérifier l’état sans correspondance.

### `3)` Vérifier la latence et les deux versions de macOS

> Préparer l’assert de la feature complète.

1. Mesurer sur le jeu mixte de 10 000 entrées de la saisie à l’affichage du premier lot, sur une série reproductible de requêtes. Relever le p95 au repos et sous indexation OCR ou archivage concurrent. Mesurer aussi pendant un export long quand ce parcours existe dans AppKite. Si le seuil manque, profiler avant de modifier l’index et rejouer la même série.
2. Exécuter le parcours complet sur Apple Silicon sous macOS 26 et 27. Couvrir menu et raccourci, deux écrans, refus et octroi des permissions, hors ligne, neuf familles, recherche et espace disque. Documenter les versions et les limites observées. La compilation pour macOS 26 et le test sur le seul hôte 27.2 ne remplacent pas le parcours sur 26.
3. Lors de l’assert, utiliser `BuildProject`, `RunAllTests` ou `RunSomeTests` et `RenderPreview` pour le bandeau et les réglages. Préparer le périmètre VCS après la revue en incluant le `.gitignore` local existant au commit et à la PR de la feature.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Une image, un PDF et une copie textuelle sont retrouvables par leur texte. Un dossier archivé est retrouvé par son nom. L’index suit les ajouts, les changements d’origine et les suppressions. |
| 2 | Recherche et filtres combinés limitent les cartes affichées, y compris les épingles. La validation au clavier colle une carte visible et sélectionnée. |
| 3 | Les premiers résultats s’affichent en moins de 200 ms au p95 sur 10 000 entrées mixtes. Les preuves de comportement couvrent macOS 26 et 27. Les mesures sous les charges applicables sont consignées. |

## État de la validation

- Sur macOS 27.2.1, Xcode a compilé le schéma `AppKite` et rendu les aperçus du bandeau et des réglages via le MCP officiel. La suite complète du dernier état via `xcodebuild` compte **46 tests réussis**, dont 5 tests d’interface. Le nouveau parcours UI saisit une recherche, vérifie l’état sans résultat et applique un filtre sans requête. Les tests Swift couvrent aussi le croisement des filtres, la recopie, la suppression, la persistance de l’OCR et le texte numérisé d’un PDF hybride.
- Mesure sur 10 000 cartes synthétiques réparties entre les neuf types, avec quatre apps sources, des sources inconnues et des épingles. Le banc Swift optimisé utilise une base SwiftData temporaire et la vraie vue SwiftUI hébergée dans une fenêtre hors écran. Sur 100 requêtes après huit passages de chauffe, le p95 de l’écriture du texte de recherche à la mise en page et au rendu demandés est de **45,45 ms** au repos et **56,88 ms** pendant 461 opérations d’archivage de 8 Mio chacune. Les requêtes alternent une correspondance large, un numéro de projet, un terme absent, un mot courant, un fragment d’URL et la requête vide. Cette mesure ne comprend pas les événements clavier ni la présentation à l’écran par le système.
- Avec deux écrans actifs, une sonde exécutant le contrôleur du bandeau a placé le pointeur sur chacun des écrans. Le panneau natif s’est ouvert centré en bas de l’écran du pointeur, à 16 points du bord de sa zone visible.
- À l’assert, le MCP Xcode a compilé le projet, exécuté les 46 tests alors présents et rendu les deux aperçus. Après correction du codec Numbers et ajout de son test de régression, `xcodebuild` a exécuté la suite complète sur macOS 27.2.1 avec **47 tests réussis**, dont 5 d’interface. La relance du build via le MCP est restée sans réponse.
- Les essais ont été effectués sur macOS 27.2.1. Yanis a demandé de retenir macOS 26 comme compatible par hypothèse, faute d’appareil disponible. Le dialogue réel d’autorisation reste à vérifier. Le collage enrichi et le repli tabulaire ont été validés dans Numbers. Le nettoyage automatique a été exercé sur un volume APFS isolé. L’export long fera l’objet de sa mesure lorsque le parcours existera. [Rapport de validation](./assert.md#round-3)
- Sur le code courant sous macOS 27.2.1, une sonde Swift optimisée a vérifié le nombre de résultats attendu pour 200 recherches sur 10 000 cartes synthétiques. Le p95 de la mise à jour du texte au premier lot disponible dans l’état du bandeau est de **44,03 ms au repos** et **47,11 ms pendant 226 archivages concurrents de 8 Mio**. Les séries comptaient 100 requêtes chacune après échauffement. Ce passage mesure l’état SwiftUI. Le rendu hors écran des cartes était inexploitable, ce qui laisse la latence jusqu’à l’affichage à vérifier.
- Le passage à l’écran atteint **90,50 ms au p95 au repos** et **106,16 ms au p95 pendant 497 archivages de 8 Mio**. Le banc optimisé ouvre la vraie vue SwiftUI dans une fenêtre visible et utilise une base temporaire de 10 000 cartes synthétiques. Après huit requêtes de chauffe, il mesure 100 requêtes par série, de la mise à jour de la liaison de recherche à la première image complète capturée du résultat. Un repère dans la première carte ou dans l’état vide associé à chaque requête identifie cette image. `SCStreamFrameInfo.displayTime` donne son instant de présentation par le serveur de fenêtres. Ce passage exclut le délai de livraison d’une frappe physique. Le seuil de 200 ms est satisfait dans les deux séries. [Assert Round 8](assert.md#round-8) · [Horodatage ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/displaytime).
- Clôture avec validation sur macOS 27.2.1. La compatibilité d’exécution macOS 26 reste une hypothèse acceptée par Yanis. L’essai de refus réel a été reporté avec son accord le 15 novembre 2026. [Validation de la phase 1](phase-1-validation.md#reprise-sur-macos-2721).
