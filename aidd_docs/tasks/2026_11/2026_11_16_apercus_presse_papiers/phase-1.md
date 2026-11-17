---
status: done
---

# Instruction: Copies archivées et images

## Architecture projection

> ✅ créer · ✏️ modifier · ❌ supprimer

```txt
.
├── AppKite/
│   └── Features/
│       └── ClipboardHistory/
│           ├── Domain/
│           │   └── ClipboardPreview.swift ✅
│           ├── UseCases/
│           │   └── ClipboardHistoryStore.swift ✏️
│           ├── Infrastructure/
│           │   ├── ClipboardArchive.swift ✏️
│           │   ├── ClipboardPreviewRenderer.swift ✅
│           │   └── SwiftDataClipboardHistoryStore.swift ✏️
│           └── UI/
│               ├── ClipboardHistoryState.swift ✏️
│               ├── ClipboardHistoryView.swift ✏️
│               ├── ClipboardHistoryCardView.swift ✏️
│               └── ClipboardHistoryPreviews.swift ✏️
└── AppKiteTests/
    └── ClipboardHistory/
        ├── ClipboardPreviewTests.swift ✅
        └── ClipboardHistoryPolicyTests.swift ✏️
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Relever le diff d’audit, vérifier les schémas Xcode et les hôtes macOS 26/27, préparer une archive isolée. | Le correctif précédent reste identifiable. Chaque environnement de vérification est identifié ou signalé indisponible. | cli |
| Happy path | Enregistrer un PNG directement puis par URL locale, supprimer l’original, rouvrir le stockage et demander les aperçus. | Les deux cartes gardent la même image entière et les mêmes dimensions. Le PNG archivé reste collable. | system |
| Edge case | Demander une capture très large, une image transparente et un fichier orienté par métadonnées. | Aucun bord utile n’est coupé. L’orientation et le damier correspondent au contenu. | system |
| Edge case | Changer de filtre ou retirer une carte pendant un rendu. | Les résultats de recherche arrivent avant le rendu. Aucun aperçu périmé n’est publié. | system |
| Edge case | Demander une archive manquante ou une représentation invalide. | La carte indique l’indisponibilité de son aperçu, avec nom et type connus. Les autres cartes restent utilisables. | system |
| Edge case | Demander l’aperçu d’un lien archivé qui cible un fichier hors de l’archive. | La carte affiche le lien par son nom et son type, sans lire sa cible. | system |
| Teardown | Fermer l’historique isolé et supprimer les fixtures de test. | Les tâches et les données temporaires du test sont libérées. | cli |

## Wireframe

```txt
┌─────────────────────────────────────────────────┐
│ (1) Recherche, filtres et actions               │
├─────────────────────────────────────────────────┤
│ (2) Historique horizontal                       │
│   ┌──────────────────┐   ┌──────────────────┐   │
│   │ (3) En-tête      │   │ En-tête          │   │
│   │ (4) Visuel       │   │ Visuel           │   │
│   │ (5) Pied         │   │ Pied             │   │
│   └──────────────────┘   └──────────────────┘   │
└─────────────────────────────────────────────────┘
```

1. Commandes existantes du bandeau.
2. Suite paginée de cartes.
3. Type, moment de copie et origine.
4. Image entière ou état de l’aperçu.
5. Nom affichable et dimensions.

## Tasks to do

### `1)` Fixer la base et le filet de régression

> Préserver le correctif précédent et établir la preuve de non-régression.

1. Relever le diff d’audit et ses nouveaux fichiers Swift. Sauvegarder cet état dans Git, puis ouvrir la branche des aperçus issue de `main` dans le dossier AppKite habituel. Reprendre la base d’audit sur cette branche et garder sa sauvegarde comme référence pour comparer le diff des aperçus. L’intégration de l’audit précède la PR des aperçus.
2. Exécuter les suites de stockage, de collage et de recherche existantes. Confirmer la disponibilité des deux hôtes, l’accès à la capture ScreenCaptureKit sur la fenêtre de test et la disponibilité du banc Round 8. Si le banc externe est introuvable, reprendre sa méthode documentée dans une sonde de test isolée en phase 4.
3. Ajouter des fixtures synthétiques PNG et une archive héritée, dans un dossier isolé.

### `2)` Lire et générer l’aperçu à la demande

> Dériver la représentation visible de la copie archivée.

1. Lire les éléments validés du manifeste et exposer au moteur d’aperçu des sources locales ciblées par identifiant de carte. Réutiliser les validations des chemins, garder les liens et alias comme éléments affichables par leur nom, et écarter leurs cibles de la lecture d’aperçu. Charger uniquement les données requises indépendamment de la préparation du collage.
2. Définir les états chargement, disponible et indisponible. Décoder hors de l’acteur principal, limiter les travaux simultanés et la mémoire des vignettes. Invalider au retrait de carte et vérifier l’identité du résultat avant publication.
3. Afficher un aperçu d’image à partir d’une représentation directe ou d’un fichier archivé. Garder l’orientation, l’aspect et l’alpha. Publier les dimensions d’origine et ajouter les cas large, portrait et transparence aux Previews.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | La base locale reste isolable. Les scénarios de référence et les deux environnements sont documentés. Les données des fixtures ne touchent pas l’historique de travail. |
| 2 | L’image archivée entière et ses dimensions restent visibles après suppression de l’original et réouverture. La recherche demeure disponible pendant le décodage, y compris quand une requête est annulée ou qu’un aperçu échoue. |
