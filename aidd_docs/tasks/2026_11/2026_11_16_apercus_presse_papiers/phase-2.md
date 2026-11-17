---
status: done
---

# Instruction: Documents, tableaux et dossiers

## Architecture projection

> ✅ créer · ✏️ modifier · ❌ supprimer

```txt
.
├── AppKite/
│   └── Features/
│       └── ClipboardHistory/
│           ├── Domain/
│           │   └── ClipboardPreview.swift ✏️
│           ├── Infrastructure/
│           │   ├── ClipboardArchive.swift ✏️
│           │   └── ClipboardPreviewRenderer.swift ✏️
│           └── UI/
│               ├── ClipboardHistoryCardView.swift ✏️
│               └── ClipboardHistoryPreviews.swift ✏️
└── AppKiteTests/
    └── ClipboardHistory/
        ├── ClipboardPreviewTests.swift ✏️
        └── PreviewFixtures/
            └── Document.docx ✅
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Préparer un PDF de deux pages, un DOCX avec contenu distinct, deux tableaux et une sélection mixte dans un dossier de test. | Les données attendues sont identifiables sans dépendre de fichiers personnels. | cli |
| Happy path | Archiver PDF et DOCX puis ouvrir les cartes hors ligne. | On distingue le contenu de la première page dans les deux cartes et le nom est visible. | system |
| Happy path | Copier un CSV et un TSV comme fichiers, puis copier directement des valeurs tabulaires. | Les lignes et colonnes correspondent aux valeurs de référence. | system |
| Edge case | Mettre des séparateurs et des sauts de ligne dans des champs entre guillemets, ou couper le préfixe d’un gros tableau. | Les premières lignes complètes gardent leur structure. | system |
| Edge case | Copier un dossier vide, un dossier à nombreux enfants, une sélection mixte et un document illisible. Inclure un lien vers un fichier externe. | Le compteur et les miniatures disponibles restent cohérents. Un cas illisible reste local à sa carte ou sa case. Le lien est compté et sa cible n’est pas lue. | system |
| Teardown | Effacer les copies temporaires du test. | Le stockage réel reste intact. | cli |

## Wireframe

```txt
┌────────────────────┬────────────────────┬────────────────────┐
│ (1) Type et origine│ Type et origine    │ Type et origine    │
├────────────────────┼────────────────────┼────────────────────┤
│ (2) Page entière   │ (3) Grille         │ (4) Miniatures     │
├────────────────────┼────────────────────┼────────────────────┤
│ (5) Nom            │ Nom               │ Nom et compteur    │
└────────────────────┴────────────────────┴────────────────────┘
```

1. En-tête commun des trois cartes.
2. Première page du document.
3. Premières cellules du tableau.
4. Éléments du dossier ou de la sélection.
5. Métadonnées utiles dans le pied.

## Tasks to do

### `1)` Afficher le contenu des documents

> Présenter une page lisible dont l’origine est le document archivé.

1. Rasteriser la première page du PDF direct ou archivé. Pour DOCX et formats compatibles, demander à Quick Look une vignette de contenu et distinguer le retour icône.
2. Vérifier hors ligne sur les hôtes macOS 26 et 27 que le corpus de référence produit une page réelle. Si le fournisseur DOCX manque sur un hôte, vérifier un rendu système local de repli ou soumettre l’écart à validation avant de clore la phase.

### `2)` Réutiliser la grille pour les fichiers CSV et TSV

> Garder le contenu tabulaire et son encodage.

1. Déduire le délimiteur du type de fichier conservé et lire un préfixe borné. Réutiliser le décodeur et la grammaire déjà utilisés pour les représentations directes.
2. Vérifier les guillemets, l’UTF-16, les lignes tronquées par la limite de lecture et les fichiers anciens.

### `3)` Rendre les dossiers et les sélections reconnaissables

> Afficher quelques éléments réels et un compteur.

1. Énumérer les enfants immédiats hors de l’interface. Limiter la mosaïque à quatre éléments et obtenir le compteur total de ce niveau. Partager le plafond de travaux d’aperçu.
2. Garder l’ordre archivé d’une sélection et limiter les lectures au dossier archivé. Un enfant illisible peut avoir un état indisponible dans sa case. Les liens et alias sont comptés et affichés par leur nom sans déréférencer leur cible.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Les cartes PDF et DOCX du corpus montrent leur première page entière hors ligne. Les formats sans rendu affichent leur état d’indisponibilité. |
| 2 | La même grille est produite pour les fixtures de fichiers et les valeurs directement copiées. Les séparateurs entre guillemets restent dans leur cellule. |
| 3 | Dossier et sélection montrent des miniatures du contenu et le nombre d’éléments. Le dossier vide est identifiable et un collage de la sélection restitue tous les éléments ensemble. |
