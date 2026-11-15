---
status: done
---

# Instruction: Gérer les cartes, les collections et la collecte

## Architecture projection

```txt
.
├── AppKite/
│   ├── App/
│   │   ├── AppKiteApp.swift ✏️
│   │   └── MenuBarView.swift ✏️
│   └── Features/
│       └── ClipboardHistory/
│           ├── Domain/
│           │   └── ClipboardCollection.swift ✅
│           ├── UseCases/
│           │   ├── ClipboardHistoryStore.swift
│           │   ├── ManageClipboardHistory.swift ✅
│           │   └── RecordClipboard.swift
│           ├── Infrastructure/
│           │   ├── ClipboardHistoryModels.swift
│           │   ├── ClipboardPreferences.swift
│           │   └── SwiftDataClipboardHistoryStore.swift
│           └── UI/
│               ├── ClipboardHistoryState.swift
│               ├── ClipboardHistoryView.swift
│               └── ClipboardSettingsView.swift
├── AppKiteTests/
│   └── ClipboardHistory/
│       └── ClipboardHistoryPolicyTests.swift ✅
└── AppKiteUITests/
    └── ClipboardHistoryUITests.swift ✅
```

Les fichiers sans symbole sont introduits en phase 1 et complétés ici.

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Préparer quatre cartes dont une épinglée et une dans deux collections | Les états des cartes et des collections sont visibles | system |
| Happy path | Épingler une carte, l’ajouter à deux collections puis supprimer l’une des collections | L’épingle est visible en tête. La carte reste dans l’historique et dans l’autre collection | system |
| Edge case | Vider l’historique puis demander la suppression d’une carte protégée | Le vidage protège les cartes épinglées et classées. La suppression ciblée dépend de la confirmation | system |
| Edge case | Activer une pause manuelle, relancer, copier et reprendre | La pause survit à la relance. Seule une nouvelle copie après reprise est enregistrée | system |
| Edge case | Fermer puis relancer avant ou après l’échéance d’une pause temporisée | La pause se poursuit avant l’échéance. Après échéance, la prochaine nouvelle copie est admissible | system |
| Edge case | Exclure une app après avoir archivé une carte issue de cette app, puis recopier depuis cette source et depuis une source inconnue | La carte existante est conservée, la nouvelle copie attribuée est écartée et la copie d’origine inconnue reste admissible | system |
| Edge case | Copier un contenu explicitement confidentiel avec la protection active puis désactivée | La première copie est écartée. La deuxième suit les autres règles d’admissibilité | system |
| Teardown | Supprimer les données et les réglages de la session de test | Le stockage local de référence est de nouveau vide | system |

## Wireframe

```txt
┌────────────────────────────────────────────────────┐
│ (1) Collections · actions de collection          │
├────────────────────────────────────────────────────┤
│ (2) Épingles   [carte]  [carte]                    │
│ (3) Historique [carte]  [carte]  [carte]  …         │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│ (4) Réglages de collecte · exclusions · option    │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│ (5) Confirmation de suppression · actions         │
└────────────────────────────────────────────────────┘
```

1. Accès aux collections et à leur gestion.
2. Section d’aperçus épinglés.
3. Historique et actions de la carte.
4. Gestion des apps exclues et des copies confidentielles.
5. Confirmation de la suppression définitive d’une carte protégée.

## Tasks to do

### `1)` Organiser les cartes

> Épingler et classer sans dupliquer les contenus archivés.

1. Ajouter les collections et leurs liens aux cartes dans le stockage local. Vérifier la réouverture d’un historique créé en phase 1 avec ses cartes intactes.
2. Ajouter la section des épingles et les commandes de gestion des collections. Persister les appartenances multiples. Supprimer le regroupement seul lors de la suppression d’une collection.
3. Vider uniquement les cartes ordinaires. Séparer la suppression ciblée et confirmer celle d’une carte protégée. Faire passer la suppression par le stockage pour que la phase 3 lui associe la suppression des archives.

### `2)` Mettre en pause et reprendre

> Laisser l’historique disponible pendant l’arrêt de la collecte.

1. Ajouter au menu la pause jusqu’à reprise manuelle et la pause de durée choisie. Persister l’état ou l’échéance et recalculer l’état au lancement et au réveil.
2. À la reprise, établir une nouvelle référence de compteur de presse-papiers pour enregistrer les copies suivantes. Vérifier la conservation de l’accès aux cartes pendant la pause.

### `3)` Appliquer les exclusions sur les nouvelles copies

> Rendre les décisions de confidentialité modifiables depuis les réglages.

1. Exposer la liste des apps exclues et le réglage activé par défaut pour les marqueurs explicitement confidentiels.
2. Appliquer ces règles avant l’écriture, le dédoublonnage et l’indexation. Garder l’origine inconnue admissible et préserver les cartes antérieures lors d’un changement des exclusions.
3. Vérifier la cohérence avec la matrice de provenance de la phase 1. Tester des marqueurs reconnus avec un producteur contrôlé et un exemplaire issu d’une app réelle, quand disponible.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Une carte peut être épinglée et classée dans plusieurs collections. La suppression d’une collection préserve les cartes, le vidage préserve les cartes protégées et la suppression ciblée les retire après confirmation. |
| 2 | Une pause active persiste après relance et se termine sur action manuelle ou à échéance. Les copies réalisées pendant la pause sont écartées. |
| 3 | Les exclusions par app et le réglage des copies confidentielles sont indépendants et s’appliquent aux nouvelles copies. Les cartes déjà archivées et les origines inconnues suivent les règles de la spec. |

## Validation sur macOS 27.2

- Le MCP Xcode a compilé le schéma `AppKite`, exécuté les 14 tests de la cible `AppKiteTests` et rendu les aperçus du bandeau et des réglages.
- Le lanceur de tests du MCP a expiré pendant l’activation de l’automatisation d’interface. La suite complète via `xcodebuild` a donné 17 réussites sur 18, dont la création, la sélection et la suppression d’une collection depuis le bandeau sur une base isolée. Le test du raccourci global depuis le Finder a réussi lors des deux exécutions séparées et échoué dans la suite complète.
- Une base synthétique écrite avec le code de la phase 1 s’ouvre avec l’identifiant, le texte, l’origine et la date de la carte d’origine. Les tests vérifient aussi la persistance des épingles et des appartenances multiples, le vidage et la confirmation de suppression.
- Les tests de collecte utilisent un presse-papiers privé et vérifient les pauses persistées, l’échéance, l’exclusion par origine et le réglage indépendant des copies confidentielles. Le marqueur confidentiel a été produit par une fixture de test.
