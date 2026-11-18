---
status: done
---

# Instruction: Isoler les effets du cas d’usage de collage

## Architecture projection

```txt
.
├── AppKite/
│   ├── App/
│   │   ├── AppKiteApp.swift ✏️
│   │   └── ClipboardHistoryComposition.swift ✅
│   └── Features/
│       └── ClipboardHistory/
│           ├── UseCases/
│           │   └── PasteClipboardEntry.swift ✏️
│           └── UI/
│               └── ClipboardHistoryState.swift ✏️
├── AppKiteTests/
│   └── ClipboardHistory/
│       ├── PasteClipboardEntryTests.swift ✅
│       ├── ClipboardRoundTripTests.swift ✏️
│       ├── ClipboardArchivedHistoryTests.swift ✏️
│       └── ClipboardHistoryPolicyTests.swift ✏️
└── build/
    └── validation/
        └── ClipboardPreviewLatencyProbe.swift ✏️
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Fournir des opérations enregistrant leurs appels et contrôlant les résultats. | Aucun presse-papiers réel, focus ou événement système n’est nécessaire aux tests de décisions. | cli |
| Happy path | Réussir l’écriture puis l’envoi avec un compteur toujours courant. | Résultat sent et contenu/compteur transmis aux opérations attendues. | cli |
| Edge case | Refuser l’envoi avec une écriture réussie et toujours courante. | Résultat copied ; le contenu reste disponible pour le collage manuel. | cli |
| Edge case | Échouer l’écriture ou signaler un changement avant l’écriture. | Résultat failed ou clipboardChanged ; aucun envoi. | cli |
| Edge case | Changer le compteur pendant l’attente d’envoi, ou annuler avant l’appel. | Aucun envoi accepté avec le mauvais contenu ; résultat conforme au contrat actuel. | cli |
| Edge case | Rejouer le collage de textes et fichiers sur un presse-papiers privé. | Octets, ordre, conservation de la restitution et exclusion de la réingestion inchangés. | system |

## Tasks to do

### `1)` Rendre les décisions indépendantes d’AppKit

> Donner au cas d’usage les effets dont il a besoin, sans cible système dans son contrat.

1. Remplacer ses références concrètes par trois opérations isolées sur MainActor : écrire conditionnellement un ClipboardPayload, vérifier un compteur et demander l’envoi asynchrone avec un prédicat de validité. Déclarer le résultat d’écriture côté cas d’usage et conserver les quatre Outcome existants.
2. Retirer les paramètres NSRunningApplication et l’import AppKit de PasteClipboardEntry. Préserver les gardes d’annulation et les vérifications avant/après l’attente ; ne pas assimiler un événement envoyé à une insertion observée dans l’app cible.
3. Ajouter la nouvelle suite Swift Testing avec résultats pilotés et suspension contrôlée de l’envoi. Vérifier les refus, la copie de repli et les compteurs sans effet système réel.

### `2)` Assembler les effets aux frontières de l’app

> Conserver les adaptateurs existants et la cible capturée à l’ouverture du bandeau.

1. Créer ClipboardHistoryComposition dans App. Y construire la fabrique de PasteClipboardEntry à partir du même PasteboardClient et d’un AppKitPasteTarget partagé. L’opération d’envoi capture l’objet cible fourni pour cette demande ; une cible absente renvoie le refus détectable existant.
2. Faire recevoir cette fabrique par ClipboardHistoryState et utiliser le cas d’usage sans y reconstruire les adaptateurs. Garder la capture et la restauration du focus dans la présentation existante.
3. Faire passer les constructions de production, du mode XCTest isolé et du mode inerte par l’assemblage App. Conserver le contrôle du nom de presse-papiers DEBUG et les stockages isolés. Adapter les constructeurs des tests de politique et du banc à cette fabrique.
4. Adapter les quatre appels de collage des tests d’intégration RoundTrip et ArchivedHistory à la même liaison réelle. Préparer la fixture preview avec des opérations inertes, sans dépendance de UI vers App ; ses données d’affichage restent dans la fixture existante.
5. Compiler l’app et les tests et exécuter la suite de décisions et les suites d’intégration concernées. Les adaptateurs PasteboardClient et AppKitPasteTarget ne nécessitent pas de changement pour cette phase.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Les décisions et les courses de compteur sont couvertes par des opérations contrôlées ; le cas d’usage ne connaît plus AppKit ni les classes d’Infrastructure. |
| 2 | Les parcours réels isolés utilisent les mêmes adaptateurs, la même cible et le même repli. Les chemins production, XCTest et preview compilent sans rouvrir l’historique ou le presse-papiers de travail pendant les tests. |
