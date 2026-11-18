---
status: done
---

# Instruction: Extraire la collecte et sa coordination avec les restitutions

## Architecture projection

```txt
.
├── AppKite/
│   ├── App/
│   │   └── ClipboardHistoryComposition.swift ✏️
│   └── Features/
│       └── ClipboardHistory/
│           ├── Domain/
│           │   └── ClipboardCollectionPolicy.swift ✅
│           ├── UseCases/
│           │   ├── ClipboardCollectionSource.swift ✅
│           │   └── CollectClipboardHistory.swift ✅
│           ├── Infrastructure/
│           │   ├── ClipboardPreferences.swift ✏️
│           │   └── PasteboardClient.swift ✏️
│           └── UI/
│               └── ClipboardHistoryState.swift ✏️
└── AppKiteTests/
    └── ClipboardHistory/
        ├── ClipboardCollectionTests.swift ✅
        ├── ClipboardCollectionTestSupport.swift ✅
        └── ClipboardHistoryPolicyTests.swift ✏️
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Construire le coordinateur avec source, préférences, stockage et temps contrôlés, sans état UI. | Ses règles et son cycle sont vérifiables indépendamment de la présentation. | cli |
| Happy path | Capturer des copies pendant une écriture suspendue et relancer l’indexation. | Archives dans l’ordre et avec leurs dates ; aucune demande d’indexation perdue. | cli |
| Edge case | Relancer en pause, franchir son échéance ou réparer un réglage illisible. | Protection et reprise conformes, contenu présent au moment de la reprise ignoré. | cli |
| Edge case | Combiner origine exclue/inconnue, confidentialité et sélection Finder invalide. | Admissibilité inchangée et rejet signalé une fois par compteur. | cli |
| Edge case | Échouer la lecture initiale des collections ou ouvrir deux fois le stockage. | Pas de collecte démarrée après l’échec initial ; un seul cycle pour les appels start répétés. | cli |
| Edge case | Réserver un collage pendant un nettoyage commencé ou seulement en file. | Attente du nettoyage commencé, invalidation du travail obsolète, capture des nouvelles copies maintenue. | cli |
| Edge case | Refuser la préparation, changer le presse-papiers ou annuler le collage. | Réservation libérée ; aucune suppression de la restitution utilisée et aucune collecte bloquée. | cli |
| Edge case | Faire ⌘A pendant l’ouverture à froid ou un changement de filtre. | Sélection différée appliquée aux bons résultats et abandonnée si la recherche est remplacée. | system |
| Teardown | Arrêter pendant l’attente, l’archivage ou l’indexation. | Tâches terminées, ressources libérées et aucun événement tardif publié. | cli |

## Tasks to do

### `1)` Définir les valeurs et les accès utiles à la collecte

> Éviter de déplacer une dépendance inversée dans le nouveau coordinateur.

1. Déplacer les valeurs ClipboardCollectionPause, ClipboardExcludedApplication et la qualification des réglages illisibles vers ClipboardCollectionPolicy. Conserver leurs représentations encodées, les clés existantes et les règles de réparation.
2. Définir ClipboardCollectionSource côté UseCases avec les seuls besoins observés : compteur, état de lecture, copie admissible, compteur de sélection invalide, rejet du contenu courant et contrôle d’un compteur. Déclarer l’état de lecture à cette frontière ; PasteboardClient implémente le port et peut garder des alias de compatibilité pour ses tests.
3. Fournir les opérations de lecture/écriture des préférences et la temporisation au coordinateur sous forme de closures regroupées. Les types et contrats de UseCases ne connaissent ni ClipboardPreferences ni PasteboardClient. Garder les opérations synchrones AppKit sur MainActor.

### `2)` Déplacer le cycle et son protocole de restitution

> Donner un propriétaire unique à la collecte, aux tâches et à la réservation du collage.

1. Créer CollectClipboardHistory, non observable et isolé sur MainActor pour l’orchestration. Recevoir la fabrique de stockage et les accès de la tâche 1. Réutiliser ClipboardHistoryStore et RecordClipboard ; garder la persistance, la recherche et l’OCR lourds dans leurs implémentations actuelles hors de l’acteur UI.
2. Préserver le démarrage : ouvrir une seule fois le stockage, charger les collections initiales, puis notifier ready et démarrer indexation et sondage. Projeter un état explicite opening/ready/failed pour la sélection à froid. Conserver l’intervalle de production de 180 ms et une file d’archivage distincte du sondage.
3. Déplacer la politique de pause/exclusion, la réparation, les compteurs et les signaux persistants d’échec. Émettre des événements typés sur MainActor pour la politique, la disponibilité, les mutations et l’indexation. L’UI garde la traduction en messages et décide de rafraîchir les résultats filtrés pendant l’indexation.
4. Déplacer isPasting et tout le suivi des restitutions dans le coordinateur. Réserver avant le premier await, attendre le nettoyage actif, revalider les nettoyages en file et garder la réservation pendant préparation, écriture/envoi et mise à jour de la restitution courante. Préserver les compteurs et le nettoyage des anciennes restitutions après réussite. Libérer sur chaque retour, erreur et annulation. Ne pas suspendre la capture des nouvelles copies.
5. Donner au cycle un start idempotent et un arrêt explicite qui annule puis attend les tâches possédées. Éviter une rétention forte de soi sur toute la boucle et les cycles avec la notification UI. Une fermeture du bandeau continue d’arrêter uniquement aperçus et lecture.

### `3)` Relier l’assemblage, la façade UI et les tests

> Garder les usages des vues stables et déplacer les règles vers leur propriétaire.

1. Dans ClipboardHistoryComposition, construire le client, les préférences, le stockage, le coordinateur et l’état ; relier la notification faiblement avant le démarrage. Fournir aussi les dépendances des chemins inertes et des tests isolés.
2. Retirer du State l’ouverture concrète du stockage et les tâches de collecte/indexation/nettoyage. Projeter les événements sans relire le stockage une deuxième fois au démarrage. Garder sélection, recherche, pagination, raccourci et présentation ; remplacer le test collectionTask != nil de ⌘A par l’état opening explicite.
3. Relier le parcours de collage à la réservation unique et au cas d’usage abstrait de la phase 2. Conserver les motifs de refus de lot, le message de repli et le classement après usage. Les vues de réglages et de pause gardent leurs commandes ; la façade transmet les mutations au coordinateur.
4. Porter les tests de règles depuis PolicyTests vers ClipboardCollectionTests. Regrouper les doubles de source, stockage et temps utiles dans ClipboardCollectionTestSupport. Garder dans PolicyTests les tests de projection, recherche, sélection, bootstrap et les intégrations AppKit nécessaires, sans dupliquer chaque règle.
5. Exécuter les scénarios du tableau, les tests de course de la phase 1 et les tests existants de sélection. Vérifier les champs supprimés du State et l’absence de dépendance à Infrastructure dans le coordinateur. Aucun changement de ClipboardArchive, des modèles ou du stockage n’est requis.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Valeurs encodées et clés inchangées ; les contrats de collecte sont indépendants des classes concrètes d’Infrastructure et des vues. |
| 2 | La collecte se teste sans état UI, reste ordonnée pendant l’archivage, préserve la coordination des restitutions et s’arrête sans notification tardive. |
| 3 | Les commandes, messages et résultats de l’UI restent conformes, notamment ⌘A à froid. Un seul assemblage fournit les dépendances de chaque instance. |
