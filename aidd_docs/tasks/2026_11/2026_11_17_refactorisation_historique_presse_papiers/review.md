# Revue de la séparation des responsabilités de l’historique

## Round 1

- Diff `main...3d55422`, avec les changements locaux du refactor. Les 32 fichiers du manifeste d’assert correspondent aux empreintes relues.
- Axes examinés **code**, **fonctionnel** et **pertinence**.
- Verdict **changes-requested**. Un échec du chargement initial des collections rend les archives inaccessibles même si le stockage et son index se sont ouverts.

### Critères

| Phase | Critère du plan | Résultat et preuve |
| --- | --- | --- |
| 1.1 | Référence complète et données de test isolées | Vérifié. 107 exécutions et deux mesures de référence dans [run.md](run.md#run-1). Les suites utilisent un stockage temporaire et des presse-papiers nommés. |
| 1.2 | Deux ordres concurrents exercés sans délai arbitraire | Vérifié. Barrières explicites dans `ClipboardHistoryPolicyTests.swift:212` et `:290`. Le premier collage attend un nettoyage actif. Le second scénario préserve une copie intervenue pendant la préparation. |
| 2.1 | Décisions d’écriture, d’envoi et de compteur isolées d’AppKit | Vérifié. Trois opérations injectées dans `PasteClipboardEntry.swift:18`. Six scénarios contrôlés dans `PasteClipboardEntryTests.swift`. |
| 2.2 | Mêmes adaptateurs sur les parcours réels et isolation des tests | Vérifié. Adaptateurs reliés dans `ClipboardHistoryComposition.swift`. Les tests d’intégration couvrent le collage et son repli. Les parcours XCUI isolés couvrent l’ouverture du bandeau, la sélection et les médias. Compilation et trois rendus consignés dans [assert.md](assert.md#round-1). |
| 3.1 | Règles découplées, clés et encodage conservés | Vérifié. Les types `Codable` sont déplacés sans modification des cas ou champs encodés. `ClipboardPreferences` conserve les clés et les accès existants. |
| 3.2 | Collecte testable sans vue, archivage ordonné, restitutions coordonnées, arrêt sans notification tardive | Vérifié. Propriétaire unique des tâches dans `CollectClipboardHistory.swift`. Les tests couvrent la pause, l’exclusion, le refus d’ouverture, l’indexation relancée, l’arrêt pendant l’archivage et les deux ordres concurrents. |
| 3.3 | Assemblage unique, commandes, messages et résultats conservés | Partiel. ⌘A à froid et le chemin normal passent. Un échec de lecture des collections fait perdre l’accès aux archives déjà chargées dans l’index. |
| 4.1 | Rendu contrôlé, deux travaux actifs au plus, annulation et cache | Vérifié. `ClipboardPreviewRequests.swift:73` conserve un emplacement jusqu’à la fin effective du travail. Les tests couvrent la réapparition d’une carte, la non-publication des résultats annulés et l’éviction par taille et par nombre. |
| 4.2 | Observation de la lecture dans l’aperçu, présentation et contrôles conservés | Vérifié. Lecture de `activeID` dans `ClipboardHistoryCardView.swift:245`. Les parcours audio, GIF et vidéo ainsi que les trois Previews passent dans [assert.md](assert.md#round-1). |
| 5.1 | Parcours, rendus, latence et preuves des quatre changements d’architecture | Vérifié pour les exécutions consignées. 119 tests, 124 exécutions, dont 10 tests d’interface. P95 de 92,31 ms au repos et 94,10 ms pendant le rendu, sous le seuil de 200 ms sur 10 000 entrées. |
| 5.2 | Contrôles statiques, carte du code et preuves alignées avec le candidat | Vérifié. Les fichiers correspondent au manifeste, les points d’entrée documentés existent et l’assert consigne le lint strict et le contrôle des espaces. macOS 26 reste une hypothèse acceptée. |

### Hypothèses vérifiées

- La cible de collage est capturée avant la fermeture du bandeau et le compteur est lu avant la création de la tâche de restitution. L’adaptateur AppKit reçoit le contrôle du compteur avant son envoi (`ClipboardHistoryState.swift:267`, `CollectClipboardHistory.swift:315`, `ClipboardHistoryComposition.swift:55`).
- Le moteur d’aperçus reste exécuté dans une tâche détachée et reçoit l’annulation de l’ordonnanceur (`ClipboardPreviewRequests.swift:101`).
- L’ouverture du stockage charge déjà l’index avant la lecture initiale des collections. La recherche utilise cet index et la lecture des collections effectue une requête SwiftData distincte (`SwiftDataClipboardHistoryStore.swift:61`, `:91`, `:402`). Le succès de ces deux opérations peut donc diverger.

### Constats

- 🟡 **L’accès aux archives régresse si le chargement des collections échoue.** `CollectClipboardHistory.swift:105–108` attend `collections()` avant de conserver le stockage ou de le transmettre à l’interface. En cas d’erreur, `.openingFailed` laisse le stockage de l’interface à `nil` et `refreshSearch()` s’arrête immédiatement (`ClipboardHistoryState.swift:345`, `:461`). Sur `3d55422`, `ClipboardHistoryState.swift:480–488` conservait le stockage avant cette lecture. Une réouverture du bandeau relançait donc la recherche sur l’index disponible (`:109–122`). Exposer le stockage ouvert aux deux consommateurs, distinguer le résultat du chargement des collections et garder la collecte inactive sur cet échec comme auparavant. Ajouter un scénario où `open()` réussit et `collections()` échoue, puis vérifier que la recherche et le collage d’une carte archivée restent possibles.

### Limites

- La revue s’appuie sur les preuves Xcode du candidat et la lecture des chemins d’erreur. Le scénario de lecture des collections en échec n’a pas été exécuté. Le test de refus d’ouverture existant fait échouer `open()`.
- L’exécution est attestée sous macOS 27.2.1. La compatibilité macOS 26 reste celle retenue par hypothèse dans la spec.
- Le cadrage, la spec et le plan référencent `../2026_11_17_audit/architecture.md`. Ce rapport antérieur existe dans la copie locale et figure hors périmètre dans le manifeste initial. Les liens dépendront de la présence de cette source dans un clone après publication.

## Round 2

- Diff `main...3d55422`, avec les changements locaux du refactor et la correction de démarrage. Les 32 empreintes de l’assert correspondent au candidat relu avant rédaction de ce rapport.
- Axes examinés **code**, **fonctionnel** et **pertinence**.
- Verdict **approve**. Le stockage ouvert reste accessible à la recherche et à la restitution si la lecture des collections échoue. Les critères du plan sont satisfaits sur le périmètre de validation convenu.

### Critères

| Phase | Critère du plan | Résultat et preuve |
| --- | --- | --- |
| 1.1 | Référence et données de test isolées | Vérifié. Le [premier run](run.md#run-1) consigne la référence sur 107 exécutions et les mesures sur stockage temporaire. |
| 1.2 | Deux ordres entre nettoyage et collage | Vérifié. Les tests à barrières de `ClipboardHistoryPolicyTests.swift:212` et `:290` passent. |
| 2.1 | Décisions de collage isolées d’AppKit | Vérifié. Les opérations de `PasteClipboardEntry.swift:18` et les tests contrôlés couvrent écriture, envoi, repli et changement de compteur. |
| 2.2 | Adaptateurs réels et isolation des parcours de test | Vérifié. Assemblage dans `ClipboardHistoryComposition.swift`. Les tests de restitution et les parcours d’interface isolés passent dans l’[assert](assert.md#round-2). |
| 3.1 | Politique indépendante des adaptateurs et clés conservées | Vérifié. `ClipboardCollectionPolicy.swift` conserve la représentation des valeurs et `ClipboardPreferences` les clés et la sérialisation. |
| 3.2 | Collecte ordonnée, restitutions coordonnées et arrêt | Vérifié. `CollectClipboardHistory.swift:121` maintient un travailleur séquentiel distinct du sondage. Les tests couvrent l’archivage suspendu, la coordination des restitutions et l’arrêt. |
| 3.3 | Assemblage unique et conservation des parcours de démarrage | Vérifié. Le test de ⌘A à froid et `archivesRemainAccessibleWhenInitialCollectionsFail()` passent. Ce dernier vérifie l’affichage de la carte, le message de collections et les octets exacts du fichier restitué. |
| 4.1 | Rendu injecté, limite de concurrence, annulation et cache | Vérifié. `ClipboardPreviewRequests.swift:73` limite à deux les travaux encore actifs. Les tests couvrent réapparition, résultats annulés et éviction. |
| 4.2 | Observation de la lecture contenue dans l’aperçu | Vérifié. `ClipboardHistoryCardView.swift:245` lit l’état de lecture dans la sous-vue. Les parcours audio, GIF et vidéo passent et les trois Previews ont été rendues. |
| 5.1 | Vérification du candidat et budget de recherche | Vérifié. L’[assert](assert.md#round-2) consigne 120 tests, 125 exécutions dont 10 d’interface et un p95 de 99,09 ms au repos et 90,62 ms en charge, sous 200 ms sur 10 000 cartes. |
| 5.2 | Contrôles statiques et documentation du candidat | Vérifié. Lint strict, espaces et empreintes validés. La carte du code correspond aux points d’entrée et l’hypothèse macOS 26 reste explicite. |

### Chemins de démarrage vérifiés

- L’ouverture charge l’index avant de rendre le stockage. La requête des collections est indépendante (`SwiftDataClipboardHistoryStore.swift:61`, `:91`, `:402`). `CollectClipboardHistory.swift:105–118` conserve le stockage et le transmet à l’interface avant cette requête. Recherche et restitution utilisent tous deux le stockage ouvert (`ClipboardHistoryState.swift:339`, `:468`, `CollectClipboardHistory.swift:334`).
- Si la requête des collections échoue, le coordinateur termine le démarrage avant de lancer l’indexation ou le sondage. L’interface ferme l’état d’ouverture, efface la sélection en attente et relance la recherche avec un message ciblé (`CollectClipboardHistory.swift:110–119`, `ClipboardHistoryState.swift:354–358`). Si `open()` échoue, le message d’ouverture reste spécifique au motif, dont le verrou d’une autre instance (`CollectClipboardHistory.swift:139–144`).
- L’événement de disponibilité normale applique les collections avant de relancer la recherche (`ClipboardHistoryState.swift:342–346`). La vérification d’annulation encadre les deux étapes du démarrage et la fermeture du cycle supprime les notifications tardives (`CollectClipboardHistory.swift:106`, `:117`, `:150`, `:374`).

### Limites

- Le test de régression force l’erreur de lecture des collections sur un substitut isolé. Les tests d’interface et la sonde de latence vérifient le candidat sur macOS 27.2.1. Le périmètre macOS 26 reste celui validé dans la spec.
- La disponibilité de l’audit source pour les liens du cadrage, de la spec et du plan dépend de son inclusion dans une version publiée. Son fichier est présent localement et figure dans le périmètre exclu au démarrage de l’implémentation.
