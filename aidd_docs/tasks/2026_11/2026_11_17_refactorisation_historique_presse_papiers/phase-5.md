---
status: done
---

# Instruction: Vérifier les parcours, les performances et les repères du projet

## Architecture projection

```txt
.
├── build/
│   └── validation/
│       └── ClipboardPreviewLatencyProbe.swift ✏️
└── aidd_docs/
    ├── memory/
    │   └── codebase-map.md ✏️
    └── tasks/
        └── 2026_11/
            └── 2026_11_17_refactorisation_historique_presse_papiers/
                └── run.md ✏️
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Utiliser le projet habituel, des données temporaires et le banc visible de la phase 1. | Source, hôte et corpus identifiés, capture limitée à la fenêtre de la sonde. | system |
| Happy path | Rejouer les parcours de menu/raccourci, recherche, collections, sélection et collage. | Mêmes résultats utilisateur et même isolation des données. | system |
| Edge case | Supprimer les originaux audio/GIF/MOV archivés puis relancer et lire leurs cartes. | Lecture depuis l’archive et arrêt à la fermeture ; collage toujours disponible. | system |
| Edge case | Rejouer les refus du collage groupé, la sélection à froid et les erreurs partielles de collecte. | Refus, protections, messages et restitutions précédentes préservés. | system |
| Edge case | Mesurer 100 recherches après huit échauffements, au repos puis avec 12 demandes d’aperçus archivés. | Premiers résultats présentés sous 200 ms au p95 sur 10 000 cartes dans les deux séries. | system |
| Teardown | Fermer les lecteurs, terminer l’app de test et supprimer les données temporaires. | Aucun accès prolongé aux données ni au presse-papiers du compte. | cli |

## Tasks to do

### `1)` Vérifier les contrats sur le candidat intégré

> Terminer les vérifications prévues avant de remettre le candidat à l’assert et à la revue.

1. Via le MCP Xcode, effectuer BuildProject, RunAllTests et la lecture du résultat complet, puis RenderPreview pour les deux variantes du bandeau et les réglages pertinents. Contrôler les résultats de tous les nouveaux tests et les dix parcours UI existants, sans déduire leur réussite d’une compilation.
2. Relire les quatre frontières de la spec : coordinateur sans état UI/adaptateur concret, collage indépendant d’AppKit, opération de rendu injectée et observation média dans la sous-vue. Préserver les tests réels des neuf familles, des archives, de l’OCR, des protections et des restitutions.
3. Mettre à jour le constructeur de ClipboardPreviewRequests dans le banc local pour qu’il utilise le rendu réellement assemblé par App. Garder la même base de 10 000 cartes, les 12 PNG archivés, deux travaux au plus, huit échauffements et 100 échantillons par série.
4. Exécuter le mode à l’écran de ce banc avec l’horodatage ScreenCaptureKit. Les deux p95 doivent rester sous 200 ms et la série chargée doit contenir des rendus réellement terminés. Le mode publication-only reste un diagnostic, pas un substitut à cette preuve. En cas d’écart, profiler la régression avant de modifier un moteur hors périmètre.

### `2)` Clore les contrôles et les repères documentaires

> Fournir les preuves utiles à l’assert puis à la revue, sans anticiper les opérations Git soumises au go.

1. Exécuter git diff --check sur le diff suivi, vérifier aussi les espaces des nouveaux fichiers et lancer xcrun swift-format lint --strict sur tous les fichiers Swift créés ou modifiés. Ces contrôles complètent l’ordre de validation de coding-assertions.md ; CONTRIBUTING.md n’en ajoute pas d’autre.
2. Actualiser codebase-map.md pour pointer vers l’assemblage App et le coordinateur effectifs. Garder les règles d’architecture, les contrats de stockage et les anciens rapports inchangés, car leurs décisions restent applicables.
3. Compléter run.md avec le commit de base, les suites et comptes réels, les rendus, les deux séries de latence et les limites. Les artefacts du banc restent dans build/validation, hors du futur commit ; les nouveaux tests utiles font partie du code versionné.
4. Demander ensuite l’assert AIDD puis la revue en lecture seule selon le flux du projet. Un échec retourne à l’implémentation avant de rejouer l’assert et la revue. Ni commit, push, PR ni fusion dans cette phase.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Les suites, parcours et rendus du candidat passent et les deux p95 à l’écran satisfont la spec ; chaque constat d’audit possède sa preuve de correction. |
| 2 | Espaces et lint strict passent sur le périmètre complet ; carte du code et preuves correspondent au candidat. macOS 26 reste explicitement une hypothèse acceptée, sans nouvelle revendication de validation en exécution. |
