---
status: done
---

# Instruction: Lecture dans la carte et validation intégrée

## Architecture projection

> ✅ créer · ✏️ modifier · ❌ supprimer

```txt
.
├── AppKite/
│   ├── App/
│   │   └── AppKiteApp.swift ✏️
│   └── Features/
│       └── ClipboardHistory/
│           └── UI/
│               ├── ClipboardHistoryState.swift ✏️
│               ├── ClipboardHistoryView.swift ✏️
│               ├── ClipboardHistoryCardView.swift ✏️
│               ├── ClipboardHistoryPreviews.swift ✏️
│               ├── ClipboardPanelController.swift ✏️
│               └── ClipboardPreviewPlayback.swift ✅
├── AppKiteTests/
│   └── ClipboardHistory/
│       ├── ClipboardPlaybackTests.swift ✅
│       └── ClipboardPreviewLatencyProbe.swift ✅ si le banc Round 8 doit être repris
└── AppKiteUITests/
    ├── IsolatedAppKite.swift ✏️
    └── ClipboardHistoryUITests.swift ✏️
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Lancer l’app de test avec un historique et un presse-papiers privés. Charger le corpus et le jeu mixte de 10 000 entrées. | Les tests sont séparés des copies réelles et disposent des mêmes scénarios sur les deux macOS. | system |
| Happy path | Ouvrir le bandeau, jouer puis mettre en pause audio, vidéo et GIF. | Aucun média ne démarre à l’ouverture. Le bouton pilote uniquement la lecture et la progression audio reflète le temps joué. | system |
| Happy path | Supprimer les originaux d’un MOV, d’un M4A et d’un GIF déjà archivés, puis relancer AppKite et jouer chaque carte. | L’image, le son et l’animation proviennent des copies archivées et se lisent encore dans la carte. | system |
| Edge case | Démarrer un second média, changer de filtre, retirer la carte, fermer avec Échap, quitter le focus ou coller. | Une seule lecture est active. Les fermetures et disparitions mettent fin à la lecture et libèrent ses ressources. | system |
| Edge case | Cliquer hors du bouton média et presser Entrée sur une autre carte, depuis le Finder. | L’action colle dans la cible attendue. Le focus, les actions de carte et les collections restent disponibles. | system |
| Edge case | Lancer des rendus lents et des recherches sur 10 000 entrées avec archives volumineuses. | Les premiers résultats visibles restent sous 200 ms au p95. Le bandeau répond pendant le traitement et retrouve sa mémoire de repos après fermeture. | system |
| Teardown | Fermer l’app, libérer le presse-papiers privé et retirer les archives du corpus de test. | Le stockage et le presse-papiers de travail sont préservés. | cli |

## Wireframe

```txt
┌───────────────────────────┐
│ (1) Type, heure et origine│
├───────────────────────────┤
│ (2) Média dans la carte   │
│      (3) Contrôle         │
│ (4) Indicateur de temps   │
├───────────────────────────┤
│ (5) Nom et métadonnées    │
└───────────────────────────┘
```

1. En-tête de la carte.
2. Image, animation, vidéo, pochette ou forme d’onde.
3. Cible accessible de lecture et de pause.
4. Progression pour les médias qui ont une durée.
5. Nom et informations d’identification.

## Tasks to do

### `1)` Isoler lecture et collage

> Commander les médias dans la carte avec le même comportement clavier de collage.

1. Donner au bouton Lecture/Pause et à la zone Coller des cibles SwiftUI sœurs. Conserver la navigation de carte, le menu contextuel et Entrée lorsque la carte est sélectionnée. Vérifier le focus et les libellés accessibles.
2. Garder une session par bandeau. Utiliser la source locale archivée pour AVPlayer et une animation GIF annulable. Piloter la progression depuis le temps effectivement joué et libérer les observateurs à l’arrêt.
3. Relier l’arrêt à la fermeture effective du panneau, y compris perte de focus et collage, ainsi qu’au retrait de la carte visible. Vérifier l’arrêt même lorsqu’un média se charge encore.

### `2)` Vérifier l’ensemble selon les assertions AppKite

> Prouver le rendu, la persistance et l’absence de régression.

1. Injecter en DEBUG un nom de presse-papiers unique partagé entre le test et l’app. Quand le mode de test est demandé, refuser un nom absent ou invalide sans ouvrir le presse-papiers général. Alimenter ce presse-papiers privé avec le corpus synthétique. Rejouer ouverture via menu et raccourci, recherche, pagination, collections, fermeture et collage.
2. Refaire la mesure à l’écran du [Round 8](../2026_11_09_historique_presse_papiers/assert.md#round-8) avec les mêmes bornes au repos puis avec génération d’aperçus actifs. Si nécessaire, reprendre la sonde selon la méthode documentée au Round 8 avec un flux ScreenCaptureKit limité à la fenêtre de test. Exercer aussi la relance avec une archive antérieure et un original supprimé.
3. Compiler le schéma AppKite avec BuildProject, exécuter les suites pertinentes et rendre les Previews large et compacte adaptées au média. Consigner la matrice de formats, les limites éventuelles macOS 26/27 et le résultat de `git diff --check` ainsi que du lint Swift strict sur les fichiers touchés.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Audio, vidéo et GIF se lisent encore après suppression des originaux et relance. La pause et la fermeture interrompent la lecture. Le reste de la carte et Entrée collent avec le comportement historique. |
| 2 | Le corpus couvre chaque famille de la spec. Les deux hôtes sont vérifiés ou un écart explicite reste ouvert. La mesure à l’écran reste sous 200 ms au p95 et les Previews se rendent. |
