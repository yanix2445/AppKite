# Run: Séparer les responsabilités de l’historique

## Run 1

- Head: `3d5542222558989280f9a5862b9826cf043ff346`
- Left: Assert AIDD et revue après validation de l’implémentation. Les changements restent locaux sur refactor/responsabilites-historique.
- Hôte : Apple Silicon, macOS 27.2.1, Xcode 27.2 (27B52), les 17 et 18 novembre 2026.
- Preuves locales : build/validation/refactor-historique.i4la7aik/.

| Task | Validation | Result |
| --- | --- | --- |
| 1.1 | MCP Xcode BuildProject puis RunAllTests avant changement de production ; banc existant compilé et exécuté à l’écran avec des données temporaires. | Compilation réussie. 107 exécutions réussies, zéro échec/ignoré/non exécuté. Capture et automatisation disponibles. Sur 100 recherches par série, p95 de 104,17 ms au repos et 97,13 ms avec les demandes d’aperçus d’archives ; seuil inférieur à 200 ms. |
| 1.2 | Ajout des deux tests de coordination dans ClipboardHistoryPolicyTests ; BuildProject puis RunSomeTests sur cette suite. | 17 exécutions réussies, dont les deux nouveaux cas. Un collage attend le nettoyage déjà commencé ; la collecte continue pendant la préparation d’une restitution et préserve une copie plus récente. Les barrières sont libérées et l’état est relâché au teardown. L’isolation du helper d’itération a été explicitée avec next(isolation:) après un premier diagnostic du compilateur. Aucun code de production modifié pendant cette phase. |
| 2.1 | BuildProject et six tests Swift Testing des décisions de collage. | Écriture, envoi, repli, changement du compteur et annulation exercés par des opérations pilotées. |
| 2.2 | RunAllTests, puis test audio ciblé via xcodebuild le 18 novembre. | 114 réussites sur 115 à la première passe. Le test audio échouait en attendant le contrôle de lecture avant le retrait de l’original et réussit seul en relance. RunSomeTests ne résolvait pas son identifiant XCTest. Relance complète prévue sur le candidat intégré. |
| 3.1 | BuildProject et cas de pause et d’exclusion avec une source et des préférences contrôlées. | Valeurs encodées et clés conservées. Le coordinateur utilise des contrats de collecte et du stockage sans adaptateur concret. |
| 3.2 | RunSomeTests pour le coordinateur, les politiques, le collage et les restitutions. | 39 exécutions réussies. Les courses du filet initial passent avec le nouveau propriétaire. Arrêt pendant l’archivage et ouverture refusée exercés sans vue. |
| 3.3 | Tests de projection et de sélection par ⌘A. | Événements mappés dans l’état du bandeau. Les scénarios de sélection au démarrage, pendant une recherche et au-delà de la première page passent. |
| 4.1 | BuildProject et RunSomeTests sur le rendu, la lecture et le nouvel ordonnanceur. | 27 exécutions réussies. Rendu injecté, annulation relayée, deux tâches actives au maximum, résultat obsolète écarté et cache vérifié sur les seuils de nombre et de poids. |
| 4.2 | Relecture de la sous-vue et RenderPreview sur macOS 27.2.1. | L’observation de la lecture se trouve dans la zone d’aperçu. Les variantes Liquid Glass et compacte ainsi que les réglages ont été rendus sans erreur. |
| 5.1 | BuildProject, RunAllTests, RunSomeTests, trois Previews et mesure à l’écran du candidat intégré. | 123 exécutions réussies lors du passage complet, dont 10 d’interface. Le scénario ajouté pendant cette passe est marqué non exécuté par le MCP et réussit lors de la relance ciblée des cinq tests du coordinateur. Les 124 exécutions attendues sont donc couvertes sans échec. Les trois Previews sont rendues et inspectées. Sur 10 000 cartes et 100 mesures par série, p95 de 98,10 ms au repos et 90,09 ms pendant le rendu. |
| 5.2 | Lint strict des 21 sources Swift du diff, contrôle des espaces et vérification des liens de la carte du code. | Contrôles réussis. Les preuves sont conservées dans le dossier local indiqué ci-dessus. Exécution vérifiée sous macOS 27.2.1. L’accord sur macOS 26 reste celui consigné dans la spec. |

Le nombre 107 décrit les exécutions retournées par le MCP, tests paramétrés compris. La compilation seule n’est pas utilisée comme preuve des tests. La mesure du banc utilise le mode à l’écran ; son mode publication-only n’a pas servi de substitut.

Le résultat xcresult signale encore des avertissements d’exécution sur le thread principal et les priorités de threads, catégories déjà consignées dans les asserts des aperçus. Le parcours audio qui avait échoué en phase 2 a réussi dans le passage final.

## Run 2

- Head: `3d5542222558989280f9a5862b9826cf043ff346`
- Left: Rejouer l’assert complet puis la revue sur le candidat corrigé. Les changements restent locaux sur `refactor/responsabilites-historique`.
- Périmètre de la reprise défini dans la [revue](review.md#round-1). Exécution ciblée avec l’intégration Xcode sur macOS 27.2.1. Rapports bruts dans `build/validation/collections-startup.9Op2MAk4/`.

| Task | Validation | Result |
| --- | --- | --- |
| 1.1 | Référence initiale | Mesures avant refactor conservées dans le [run 1](#run-1). |
| 1.2 | `RunSomeTests` · courses du nettoyage et du collage | Les deux scénarios passent dans `ClipboardHistoryPolicyTests`. |
| 2.1 | Décisions de collage | Preuves de la phase 2 dans le [run 1](#run-1). |
| 2.2 | `RunSomeTests` · collage et archivage | Les suites `ClipboardRoundTripTests` et `ClipboardArchivedHistoryTests` passent. |
| 3.1 | `RunSomeTests` · règles de collecte | Les scénarios de pause, reprise et exclusion passent. |
| 3.2 | `RunSomeTests` · cycle et restitutions | Les tests du coordinateur passent. La collecte et l’indexation démarrent après la lecture réussie des collections. |
| 3.3 | `BuildProject` et `RunSomeTests` · démarrage avec échec de lecture des collections | Le nouveau test échoue avant correction au moment de retrouver la carte. Après correction, la carte apparaît dans la recherche et le fichier restitué contient les octets archivés. La sélection à froid passe aussi. Les cinq suites ciblées totalisent 37 tests et 38 exécutions réussies. |
| 4.1 | File et cache des rendus | Preuves d’implémentation dans le [run 1](#run-1). |
| 4.2 | Contrôles de lecture et Previews | Preuves d’implémentation dans le [run 1](#run-1). |
| 5.1 | Vérification du candidat corrigé | Compilation et suites ciblées réussies. La suite complète, les Previews et la mesure à l’écran relèvent de l’assert suivant. |
| 5.2 | `git diff HEAD --check` et lint Swift strict | Contrôles réussis sur la correction. |
