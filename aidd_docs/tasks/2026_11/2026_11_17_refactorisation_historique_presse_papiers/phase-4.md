---
status: done
---

# Instruction: Injecter le rendu et isoler la zone d’aperçu des cartes

## Architecture projection

```txt
.
├── AppKite/
│   ├── App/
│   │   └── ClipboardHistoryComposition.swift ✏️
│   └── Features/
│       └── ClipboardHistory/
│           ├── UseCases/
│           │   └── RenderClipboardPreview.swift ✅
│           └── UI/
│               ├── ClipboardPreviewRequests.swift ✏️
│               ├── ClipboardHistoryState.swift ✏️
│               └── ClipboardHistoryCardView.swift ✏️
└── AppKiteTests/
    └── ClipboardHistory/
        └── ClipboardPreviewRequestsTests.swift ✅
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Fournir un rendu contrôlé avec événements et barrières. | Les tests de file/cache ne passent pas par les moteurs réels. | cli |
| Happy path | Montrer trois cartes, bloquer les deux premiers rendus puis en terminer un. | Deux travaux actifs au maximum ; le troisième démarre après une fin effective. | cli |
| Edge case | Masquer une carte en attente ou terminer un ancien rendu après hide/reset. | Pas d’appel pour la carte retirée avant démarrage ; aucun résultat périmé publié. | cli |
| Edge case | Réinitialiser avec deux travaux qui ignorent temporairement l’annulation, puis réafficher le même UUID. | Les anciens travaux gardent leurs slots jusqu’à leur fin ; seul le nouveau résultat est publié. | cli |
| Edge case | Réafficher une carte en cache puis dépasser les seuils en nombre et en poids. | Pas de nouveau rendu sur hit ; éviction LRU des seuls résultats non visibles. | cli |
| Edge case | Retourner source absente, rendu nil ou erreur de stockage. | Résumé ou aperçu indisponible avec les mêmes nom/type qu’avant. | cli |
| Edge case | Lancer, suspendre et changer une lecture puis coller ou fermer. | Zone média mise à jour, en-tête/pied indépendants de l’état de lecture, actions et arrêt inchangés. | system |
| Teardown | Annuler les demandes et libérer les barrières. | Tous les travaux du test terminent avant la fin de sa fixture. | cli |

## Wireframe

```txt
┌─────────────────────────────┐
│ (1) En-tête                 │
├─────────────────────────────┤
│ (2) Zone d’aperçu            │
│        (3) Contrôle média    │
├─────────────────────────────┤
│ (4) Pied et métadonnées     │
└─────────────────────────────┘
```

1. En-tête existant avec type, date et origine.
2. Section existante devenue frontière d’observation indépendante.
3. Contrôle existant conservant sa cible distincte du collage.
4. Nom et détails existants, sans observation de l’état de lecture.

## Tasks to do

### `1)` Substituer le rendu sans déplacer l’ordonnanceur

> Fournir une opération contrôlable tout en gardant les invariants des demandes visibles.

1. Déclarer RenderClipboardPreview dans UseCases comme une opération Sendable de ClipboardPreviewSource vers un ClipboardPreview optionnel, asynchrone. La recevoir dans ClipboardPreviewRequests ; App compose l’appel réel à ClipboardPreviewRenderer et ClipboardMediaPreview.
2. Garder la lecture de source via ClipboardHistoryStore, la traduction des erreurs, la file, le cache et la visibilité dans Requests. Capturer l’opération sans retenir l’objet entier pendant le chargement. Conserver la tâche détachée de priorité utility et son relais d’annulation.
3. Préserver le comptage des jobs annulés jusqu’à leur fin réelle : reset ne libère pas leurs slots prématurément. Publier seulement pour une demande encore visible et non annulée. Vérifier le cas du même UUID réapparu avant la fin du travail précédent.
4. Garder les seuils existants de 48 résultats et 24 Mio pour les PNG d’images/mosaïques, avec éviction des seuls non visibles. Ne pas transformer ces seuils en plafond strict supprimant un aperçu visible. Fournir une opération inerte à la fixture preview existante.
5. Ajouter les tests du tableau. Utiliser les événements du moteur contrôlé pour synchroniser les démarrages et les fins ; une confirmation ne remplace pas l’attente effective. Garder les tests d’intégration actuels des moteurs, du stockage et du lecteur.

### `2)` Donner sa propre frontière à la zone d’aperçu

> Déplacer la dépendance de lecture sans changer le dessin de la carte.

1. Créer une struct View privée dans ClipboardHistoryCardView.swift et y déplacer le bloc preview. Passer les seules données qu’il utilise et la référence stable de ClipboardPreviewPlayback. La lecture de activeID a lieu dans le body de cette sous-vue.
2. Conserver le calcul partagé de couleur, les branches de repli, les modificateurs et les identifiants accessibles. L’API de la carte et les fichiers ArchivedPreviewView, Playback et HistoryView restent inchangés.
3. Vérifier par lecture des dépendances que le body de la carte, son en-tête et son pied ne lisent plus l’état de lecture. Éviter un test fragile comptant les évaluations internes de body ou l’annonce d’un gain non mesuré.
4. Compiler, exécuter les nouvelles suites et les intégrations d’aperçus/lecture, puis rendre les Previews large et compacte existantes pour comparer la structure du wireframe.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Un faux rendu suffit à vérifier la file, l’annulation et le cache ; les deux travaux réellement actifs restent la borne et aucun ancien résultat n’est publié. |
| 2 | La lecture de l’état média se trouve dans la sous-vue d’aperçu ; apparence, contrôles, collage et états de repli sont conservés dans les tests et les rendus. |
