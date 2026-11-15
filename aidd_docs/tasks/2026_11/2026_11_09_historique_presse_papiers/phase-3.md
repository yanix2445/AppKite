---
status: done
---

# Instruction: Restituer les formats et gérer les archives sur disque

## Architecture projection

```txt
.
├── AppKite/
│   └── Features/
│       └── ClipboardHistory/
│           ├── Domain/
│           │   ├── ClipboardEntry.swift
│           │   └── ClipboardPayload.swift ✅
│           ├── UseCases/
│           │   ├── ClipboardHistoryStore.swift
│           │   ├── ManageClipboardHistory.swift
│           │   ├── PasteClipboardEntry.swift
│           │   └── RecordClipboard.swift
│           ├── Infrastructure/
│           │   ├── ClipboardArchive.swift ✅
│           │   ├── ClipboardFormatCodec.swift ✅
│           │   ├── ClipboardHistoryModels.swift
│           │   ├── PasteboardClient.swift
│           │   └── SwiftDataClipboardHistoryStore.swift
│           └── UI/
│               ├── ClipboardHistoryState.swift
│               └── ClipboardHistoryView.swift
└── AppKiteTests/
    └── ClipboardHistory/
        ├── ClipboardFormatTests.swift ✅
        └── ClipboardArchiveTests.swift ✅
```

Les fichiers sans symbole sont introduits dans les phases précédentes et complétés ici.

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Préparer les neuf familles dans un volume de test et des apps destinataires compatibles | Les fixtures ont des résultats de collage attendus et un historique isolé | system |
| Happy path | Copier puis recoller chaque famille, dont un tableau avec formules et une sélection Finder | Les contenus gardent les représentations utiles et les sélections se recollent en bloc | system |
| Edge case | Coller une plage dans une destination qui accepte les valeurs tabulaires | Les valeurs restent dans les lignes et colonnes d’origine | system |
| Edge case | Supprimer les originaux d’un dossier et d’une sélection de fichiers déjà archivés | Les cartes restent recollables et les éléments correspondent aux originaux archivés | system |
| Edge case | Relancer avec une carte ordinaire ancienne et suffisamment d’espace, puis archiver un contenu volumineux qui tient sur le volume | La carte ancienne est conservée et la copie volumineuse est archivée | system |
| Edge case | Faire échouer la lecture d’un fichier sur cinq ou interrompre une écriture | Aucune carte partielle ni référence à un fichier manquant. Les restes sont réconciliés à la reprise | system |
| Edge case | Imposer une place récupérable insuffisante sur le volume de test | L’historique est conservé et l’échec d’archivage est signalé | system |
| Edge case | Préparer une éviction possible avec des cartes protégées et des cartes ordinaires réutilisées | Le nettoyage part des cartes ordinaires utilisées le moins récemment et s’arrête quand la place suffit | system |
| Edge case | Présenter des fichiers clonés, une variation d’espace ou une panne après préparation | La mesure tient compte de l’espace réellement disponible. La reprise expose un historique cohérent | system |
| Edge case | Supprimer une carte protégée après confirmation et rouvrir l’historique | La carte et le contenu associé ne sont plus disponibles | system |
| Teardown | Retirer le volume isolé et les fixtures | Les archives personnelles du Mac restent hors du volume de test | system |

## Tasks to do

### `1)` Conserver les représentations utiles des neuf familles

> Garder la fidélité du collage et un aperçu léger pour chaque carte.

1. Étendre la capture aux éléments ordonnés et à leurs formats supportés. Garder le texte brut associé au texte enrichi, les valeurs tabulaires à côté du format riche fourni, les URL, les images, les PDF, les couleurs et les pièces jointes des contenus mixtes. Séparer les marqueurs de contrôle des données à recoller.
2. Reconstituer les représentations acceptées lors du collage. Vérifier les neuf familles avec des fixtures et des apps capables de les restituer. Pour les tableurs, essayer au moins le collage enrichi dans l’app source et le collage des valeurs dans une destination compatible.
3. Calculer l’identité d’une copie à partir des contenus et de la structure qui influencent la restitution. Préserver une carte existante lors d’un vrai doublon et distinguer des contenus dont le collage diffère. Produire des résumés et des aperçus hors de l’acteur d’interface pour la rangée existante.

### `2)` Archiver les sélections du Finder et les gros contenus

> Publier une carte seulement quand le contenu entier est disponible.

1. Archiver localement les éléments Finder avec leurs noms et leurs groupes. Copier dans un emplacement temporaire du stockage, avec opérations de fichiers hors de l’acteur d’interface. Valider la sélection entière et la stabilité de la source avant la publication.
2. Publier les métadonnées après disponibilité du contenu complet. En cas d’échec, nettoyer l’archive temporaire et signaler l’échec. Réconcilier à la relance les opérations interrompues et les fichiers orphelins. La suppression confirmée retire la carte et son archive, avec reprise en cas d’échec partiel.
3. Restaurer une sélection depuis ses copies archivées et vérifier le collage après suppression des originaux. Vérifier une sélection volumineuse et une source sur un volume distinct. L’archivage dépend de la capacité du volume, avec une conservation sans expiration automatique ni plafond de taille fixé par AppKite.

### `3)` Évaluer puis libérer l’espace récupérable

> Protéger les cartes épinglées et classées tout en archivant les nouvelles copies qui tiennent sur le volume.

1. Mesurer la capacité du volume d’archive et estimer le besoin réel, y compris l’écriture des métadonnées. Déterminer si les candidats libéreront suffisamment d’espace avant toute suppression. Vérifier le comportement réel sur un volume de test contraint et tester les clones APFS dont les blocs restent partagés.
2. Sérialiser le choix et la suppression des candidats, des moins récemment utilisés aux plus récents. La dernière copie ou le dernier collage, selon l’événement le plus récent, fixe cet ordre. Revérifier les protections et la capacité. Arrêter quand l’espace suffit.
3. Si l’espace récupérable est insuffisant, conserver l’historique et signaler que la copie n’a pas été archivée. Si les API publiques ne permettent pas d’établir assez précisément l’espace récupérable dans un cas réel, préserver les cartes dans ce cas et soumettre l’écart avant acceptation. Couvrir les interruptions et l’échec tardif par les vérifications de cohérence du stockage.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Les neuf familles se recollent selon les capacités des apps de destination. Les cellules récupèrent leur format riche si disponible ou leurs valeurs tabulaires en repli. |
| 2 | Les fichiers et dossiers restent recollables depuis l’archive après suppression de l’original. Une sélection partiellement archivée ne crée aucune carte et l’échec est signalé. L’historique persiste sans expiration automatique et accepte les contenus volumineux sans plafond propre à AppKite lorsque la place suffit. |
| 3 | Une capacité insuffisante prévisible préserve l’historique. Si l’éviction suffit, seules des cartes ordinaires sont supprimées dans l’ordre attendu, jusqu’à pouvoir archiver la copie. |

## État de la validation

- Sur macOS 27.2.1, le MCP officiel Xcode a compilé le schéma `AppKite` et rendu l’aperçu du bandeau. La suite MCP a donné 36 réussites sur 37. Le test du raccourci global depuis le Finder a ensuite réussi seul puis dans la suite complète `xcodebuild`, qui a donné 37 réussites sur 37.
- Les neuf familles sont exercées sur un presse-papiers privé. Sur macOS 27.2.1, une plage réelle de Numbers archivée puis recollée a conservé ses quatre cellules, sa formule et la couleur de fond de la cellule calculée. Le collage limité au texte tabulaire a restitué les quatre valeurs dans les deux lignes et deux colonnes attendues. Le codec reconnaît les marqueurs de tableau émis par Numbers et enregistre les représentations natives nécessaires au collage.
- Une archive ouverte après relance restitue des fichiers et dossiers dont les originaux ont été supprimés. Les tests vérifient aussi l’abandon d’une sélection incomplète, la suppression protégée et la réconciliation des écritures interrompues. Le collage Finder reçoit une copie de travail afin que le déplacement du fichier collé préserve l’archive.
- Un volume APFS isolé de 128 Mio a permis de vérifier une archive provenant d’un autre volume et le refus d’un contenu trop grand. Après l’erreur réelle d’espace disque, la carte antérieure et son contenu restent lisibles et aucune archive temporaire n’est publiée.
- Sur un volume APFS isolé de 160 Mio, `ATTR_CMNEXT_PRIVATESIZE` a indiqué 0 octet récupérable pour une archive aux blocs partagés et 9 Mio pour une archive indépendante. Une copie trop grande a laissé les cinq cartes en place. L’archivage d’un nouveau fichier de 12 Mio a supprimé la plus ancienne carte disposant d’espace récupérable, puis la nouvelle archive a été relue après réouverture. Les cartes épinglée, classée, réutilisée récemment et aux blocs partagés ont été conservées. [Rapport de validation](./assert.md#round-3)
- La revue a établi que cette première éviction pouvait supprimer une archive avant que la nouvelle copie soit enregistrée. Le correctif intermédiaire a suspendu l’éviction. L’[assert Round 5](./assert.md#round-5) a vérifié la préservation de l’historique en cas de manque de place.
- Le nettoyage est rétabli avec une réserve APFS locale d’au plus 16 Mio. Sur une erreur d’allocation, cette réserve fournit de la place pour terminer la nouvelle archive. Une seule sauvegarde SwiftData valide ensuite la nouvelle carte et l’éviction du premier ensemble d’archives ordinaires qui couvre le déficit mesuré. Les anciens fichiers sont retirés après cette sauvegarde. La réserve est reconstituée selon la capacité du volume. Si la nouvelle archive ne peut pas être terminée ou si le déficit ne peut pas être couvert, AppKite signale l’échec et préserve les cartes existantes. [Préallocation Darwin](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/fcntl.2), [sauvegarde SwiftData](https://developer.apple.com/documentation/swiftdata/modelcontext).
- L’[assert Round 6](./assert.md#round-6) vérifie le doublon sans suppression, deux cas d’espace insuffisant, l’éviction minimale et la reprise après une interruption avant ou après la sauvegarde de la base.
