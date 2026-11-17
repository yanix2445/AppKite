---
status: done
---

# Instruction: Vignettes vidéo et audio

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
│           │   ├── ClipboardFormatCodec.swift ✏️
│           │   ├── ClipboardPreviewRenderer.swift ✏️
│           │   └── ClipboardMediaPreview.swift ✅
│           └── UI/
│               ├── ClipboardHistoryCardView.swift ✏️
│               └── ClipboardHistoryPreviews.swift ✏️
└── AppKiteTests/
    └── ClipboardHistory/
        ├── ClipboardFormatTests.swift ✏️
        └── ClipboardMediaPreviewTests.swift ✅
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Créer un MOV avec des images distinctes, deux M4A avec et sans pochette, et un GIF animé. | Chaque contenu a des métadonnées et un rendu attendus. | cli |
| Happy path | Copier les fixtures en fichiers locaux et, quand la représentation est réellement fournie, comme média direct. | Les vidéos montrent une image du contenu, les pistes leur pochette ou leur forme d’onde, et les GIF sont reconnaissables à l’arrêt. | system |
| Edge case | Examiner un média corrompu, sans piste pertinente, non décodable ou très long. | Le traitement reste borné et annulable. La carte garde son nom, son type et son action de collage. | system |
| Edge case | Archiver une liste de lecture locale qui pointe vers un flux distant ou une référence à un média externe. | L’aperçu indique l’indisponibilité. Le moteur ne charge pas le média référencé. | system |
| Edge case | Recoller un média copié directement et un fichier archivé. | Les données fournies par la copie ou l’archive restent disponibles pour la destination. | system |
| Teardown | Fermer l’historique de test et libérer les fichiers temporaires. | Aucun décodage de test ni fichier de travail ne subsiste. | cli |

## Wireframe

```txt
┌────────────────────┬────────────────────┬────────────────────┐
│ (1) Type et origine│ Type et origine    │ Type et origine    │
├────────────────────┼────────────────────┼────────────────────┤
│ (2) Image de vidéo │ (3) Pochette       │ (4) Forme d’onde  │
├────────────────────┼────────────────────┼────────────────────┤
│ (5) Nom et détails │ Nom et détails     │ Nom et détails     │
└────────────────────┴────────────────────┴────────────────────┘
```

1. En-tête commun, avec la nature du média.
2. Image issue de la vidéo.
3. Illustration embarquée dans la piste.
4. Amplitudes de l’enregistrement.
5. Nom, format, taille et durée.

## Tasks to do

### `1)` Identifier le média à partir de l’archive

> Donner le même rendu à des contenus équivalents, indépendamment de l’app source.

1. Déterminer le format à partir du fichier local ou de la représentation annoncée. Vérifier ce que fournissent une copie issue de l’enregistreur et une copie Finder sur le corpus de référence. Admettre les représentations binaires audio et vidéo compatibles via le codec existant lorsqu’elles sont effectivement disponibles localement.
2. Conserver les données originales, les catégories de recherche et le traitement existant de la pause, des exclusions et des copies confidentielles. Si une représentation binaire a besoin d’une extension pour être décodée, fournir au moteur un accès local temporaire à cette représentation archivée, borné et nettoyé. Les URL distantes restent des liens. Autoriser le décodage et la lecture uniquement pour les conteneurs locaux autonomes. Vérifier les listes de lecture et les références vers un média externe.

### `2)` Décoder une vignette et des métadonnées utiles

> Préparer une vraie image ou une vraie forme d’onde.

1. Générer l’image vidéo avec AVFoundation en respectant l’orientation, puis extraire format, taille et durée.
2. Lire la pochette audio quand elle existe. Calculer les amplitudes de la forme d’onde à partir de PCM en lecture progressive ou échantillonnée, avec un nombre fixe de barres. Annuler le calcul devenu inutile.
3. Identifier les GIF réellement animés et produire leur vue à l’arrêt. Ajouter les variantes de fiche média aux Previews. Vérifier les codecs du corpus de référence hors ligne sous macOS 26 et 27.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Les sources locales disponibles montrent les mêmes aperçus sans perte de données au collage. Un lien distant ne déclenche pas de chargement média. |
| 2 | La vidéo affiche une image du fichier, la piste avec pochette affiche sa pochette et l’autre piste affiche des amplitudes du son. Un média lourd ou illisible ne retarde pas la publication des cartes. |
