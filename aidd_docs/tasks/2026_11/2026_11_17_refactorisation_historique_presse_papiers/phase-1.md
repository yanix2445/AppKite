---
status: done
---

# Instruction: Fixer le filet de régression et les prérequis de mesure

## Architecture projection

```txt
.
├── AppKiteTests/
│   └── ClipboardHistory/
│       └── ClipboardHistoryPolicyTests.swift ✏️
└── aidd_docs/
    └── tasks/
        └── 2026_11/
            └── 2026_11_17_refactorisation_historique_presse_papiers/
                └── run.md ✅
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Ouvrir une branche refactor dans le dossier existant et vérifier l’isolation des données des tests. | Même projet, stockage et presse-papiers de test distincts des données de travail. | cli |
| Happy path | Exécuter les suites existantes, dont le démarrage à froid, les collections et les médias archivés. | Une référence complète avec les réussites, échecs et limites réels est conservée. | system |
| Edge case | Suspendre un nettoyage déjà démarré, puis demander un collage. | La préparation attend la fin du nettoyage ; la restitution produite ensuite reste disponible. | system |
| Edge case | Suspendre la préparation d’un collage et provoquer un nouveau changement de presse-papiers. | La collecte continue et un nettoyage ne retire pas la restitution en préparation. | system |
| Edge case | Vérifier les autorisations nécessaires à l’automatisation et à la capture de la seule fenêtre du banc. | Chaque prérequis est disponible ou son obstacle est résolu avant la refactorisation. | system |
| Teardown | Terminer les tâches et retirer les données de test. | Aucun processus de test ni fichier temporaire ne continue de modifier l’état. | cli |

## Tasks to do

### `1)` Établir la référence de validation

> Connaître le comportement de départ avant tout déplacement de production.

1. Créer une branche telle que refactor/responsabilites-historique depuis main dans le dossier AppKite actuel. Conserver les documents locaux existants ; aucun changement de copie de travail ni application de stash.
2. Utiliser BuildProject puis RunAllTests via le MCP Xcode et lire le résultat complet. Comparer les résultats au dernier assert documenté sans imposer son ancien nombre comme un résultat de cette passe.
3. Vérifier que le banc existant build/validation/ClipboardPreviewLatencyProbe.swift est disponible et que ses prérequis de capture sont satisfaits. Conserver son mode à l’écran et son corpus comme référence de la phase 5. Résoudre un blocage d’outillage avant d’extraire le code.
4. Créer run.md avec le commit source, l’hôte, les résultats et les obstacles éventuels. Consigner les avertissements d’exécution séparément des erreurs ou échecs de tests.

### `2)` Verrouiller la coordination des restitutions

> Protéger l’invariant partagé qui va changer de propriétaire.

1. Compléter le substitut de stockage des tests de politique avec des événements de préparation/nettoyage et des barrières que le test libère explicitement. Utiliser uniquement un presse-papiers nommé privé et une cible de collage absente.
2. Ajouter les deux scénarios de concurrence du tableau et vérifier l’ordre des opérations et la disponibilité de la restitution, avec les effets observables du contrat. Garder les tests existants de copies pendant une écriture suspendue et de ⌘A à froid.
3. Attendre les événements de progression et libérer toutes les barrières au teardown, y compris en cas d’échec. Exécuter les tests ciblés ; ne pas modifier la logique de production dans cette phase.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | La référence complète du candidat est consignée et les prérequis d’automatisation et de mesure sont disponibles. Les données de travail n’ont pas servi de fixture. |
| 2 | Les deux ordres concurrents sont exercés sans dépendre d’une temporisation arbitraire ; aucune restitution en cours d’utilisation n’est retirée et les tâches de test sont terminées. |
