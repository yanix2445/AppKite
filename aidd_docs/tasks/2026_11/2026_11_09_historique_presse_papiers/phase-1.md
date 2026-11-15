---
status: done
---

# Instruction: Copier, ouvrir et recoller du texte

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
│           │   └── ClipboardEntry.swift ✅
│           ├── UseCases/
│           │   ├── ClipboardHistoryStore.swift ✅
│           │   ├── RecordClipboard.swift ✅
│           │   └── PasteClipboardEntry.swift ✅
│           ├── Infrastructure/
│           │   ├── ClipboardHistoryModels.swift ✅
│           │   ├── SwiftDataClipboardHistoryStore.swift ✅
│           │   ├── ClipboardPreferences.swift ✅
│           │   ├── PasteboardClient.swift ✅
│           │   ├── AppKitPasteTarget.swift ✅
│           │   └── GlobalHotKey.swift ✅
│           └── UI/
│               ├── ClipboardHistoryState.swift ✅
│               ├── ClipboardPanelController.swift ✅
│               ├── ClipboardHistoryView.swift ✅
│               └── ClipboardSettingsView.swift ✅
├── AppKiteTests/
│   └── ClipboardHistory/
│       └── ClipboardRoundTripTests.swift ✅
└── AppKiteUITests/
    └── AppKiteUITests.swift ✏️
```

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Lancer une instance isolée avec un historique vide et une app de réception | Un menu AppKite, aucun bandeau au démarrage et un champ de collage connu | system |
| Happy path | Copier du texte avec accents et sauts de ligne, ouvrir au raccourci et valider avec Entrée | Le texte arrive dans l’app d’origine. Un second ⌘V recolle le même texte | system |
| Edge case | Mettre du texte dans le presse-papiers avant le lancement, puis copier après lancement | Seule la nouvelle copie admissible apparaît et persiste après relance | system |
| Edge case | Refuser la lecture, puis autoriser à nouveau l’app dans les Réglages Système | Les cartes archivées sont consultables, le bandeau explique l’arrêt et les nouvelles copies sont collectées après autorisation | system |
| Edge case | Refuser l’envoi d’événements ou fermer l’app cible avant validation | Aucun événement n’est envoyé à une autre app. L’élément est recopié et le message de repli apparaît après écriture | system |
| Edge case | Changer d’app au retour du focus ou remplacer le presse-papiers avant l’envoi | AppKite n’envoie pas de collage qui viserait la mauvaise app ou le mauvais contenu | system |
| Edge case | Ouvrir depuis le menu puis depuis le raccourci avec le pointeur sur le second écran | Le bandeau suit le pointeur. L’app destinataire correspond à l’app active capturée à l’ouverture | system |
| Edge case | Choisir un raccourci déjà réservé | Le réglage signale le conflit et le raccourci précédent reste utilisable | system |
| Edge case | Faire écrire une app en arrière-plan et changer rapidement d’app au premier plan | Une attribution non corroborée reste inconnue | system |
| Teardown | Fermer AppKite et restaurer les réglages et données de la session de vérification | L’icône et le bandeau disparaissent. Une relance recrée une seule icône | system |

## Wireframe

```txt
┌──────────────────────────────────────────────────┐
│ (1) État d’accès · action Réglages Système       │
├──────────────────────────────────────────────────┤
│ (2) Cartes · [aperçu]  [aperçu]  [aperçu]  …       │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│ (3) Réglages · enregistreur de raccourci          │
└──────────────────────────────────────────────────┘
```

1. État de lecture et accès aux réglages macOS.
2. Rangée d’aperçus et sélection au clavier.
3. Configuration du raccourci global.

## Tasks to do

### `1)` Conserver le socle de barre de menus

> Ajouter le parcours texte depuis l’icône existante.

1. Rejouer le contrôle `LSUIElement` et le cycle menu, fermeture et relance. Adapter le test d’interface à la présence des actions d’historique et de réglages et vérifier que Quitter reste disponible.
2. Composer les dépendances dans `AppKiteApp`. Garder le bandeau fermé au lancement et réutiliser le même point d’ouverture depuis le menu et le raccourci.

### `2)` Capturer et relire une carte de texte

> Établir un aller-retour local avant d’élargir les formats.

1. Initialiser la surveillance sur le compteur courant. Traiter un changement stable de `NSPasteboard.general.changeCount` et avancer le compteur sans lire le contenu quand la collecte est bloquée. Vérifier le refus ponctuel et persistant et l’ouverture des Réglages Système sur chaque version.
2. Matérialiser le texte et la provenance disponible. Qualifier l’origine avec les signaux explicites dont la sémantique est vérifiée. Examiner des copies de Safari et Mail, les écritures en arrière-plan, les bascules rapides et Handoff. Une app au premier plan seule reste un signal insuffisant. Présenter la limite à Yanis si les copies usuelles ne peuvent pas être attribuées de façon défendable.
3. Appliquer la protection par défaut des marqueurs de confidentialité reconnus avant la persistance. Conserver les changements propres à AppKite à part pour éviter leur réingestion. Valider la surveillance sur des copies rapprochées et signaler tout écart de capture observé.
4. Persister le texte, son identité, l’origine et les dates via SwiftData avec `cloudKitDatabase: .none`. Garder les appels de stockage hors de l’acteur d’interface. Une nouvelle copie identique met à jour la carte existante. La réutilisation la remonte sans remplacer sa provenance.

### `3)` Ouvrir le bandeau sur l’écran du pointeur

> Valider le raccourci et le choix d’écran en situation réelle.

1. Enregistrer exclusivement `⇧⌥V` via HIToolbox sur l’acteur principal. Persister une nouvelle combinaison après enregistrement réussi. En cas de conflit, conserver l’ancienne combinaison et l’accès par le menu.
2. Capturer séparément la cible de collage et les coordonnées du pointeur avant l’activation d’AppKite. Présenter un panneau AppKit hébergeant les cartes SwiftUI au bas de la zone visible de l’écran contenant le pointeur. Vérifier deux écrans, l’ouverture depuis le menu et le raccourci avec une disposition de clavier utilisée sur les machines de test.
3. Sélectionner la carte la plus récente à l’ouverture. Câbler Entrée et la validation à la souris vers la même action.

### `4)` Restituer le texte à l’app cible

> Coller uniquement vers le processus capturé à l’ouverture.

1. Vérifier l’autorisation d’envoi d’événements à l’usage. Préparer le contenu, l’écrire dans le presse-papiers et confirmer le retour du focus de la cible avant de lui envoyer un seul `⌘V` adressé à son PID. Vérifier que le presse-papiers contient toujours le contenu choisi avant l’envoi.
2. Quand le collage direct est indisponible de façon détectable et que l’écriture réussit, afficher « Copié. Colle avec ⌘V. ». Une écriture échouée produit un état d’échec. Vérifier l’insertion dans l’app de test et conserver la distinction entre envoi réussi et insertion effectivement observée.
3. Vérifier le cas où une app ignore l’événement. Si la limite d’observation du résultat empêche d’honorer le repli validé dans un cas pertinent, soumettre cet écart avant acceptation.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Le lancement affiche une icône, le menu expose l’historique et Quitter et la relance rétablit une seule icône. |
| 2 | Une première copie nouvelle est archivée et survit à la relance. Une copie identique conserve une seule carte. Refuser la lecture laisse l’historique accessible et affiche « Autorise l’accès au presse-papiers pour reprendre l’enregistrement » avec le bouton Ouvrir les Réglages Système. |
| 3 | Le menu et `⇧⌥V` ouvrent le bandeau sur l’écran du pointeur. La dernière carte est présélectionnée et un conflit conserve l’ancien raccourci. |
| 4 | Entrée colle dans la bonne app lorsque le parcours le permet et le prochain ⌘V garde le contenu choisi. Une cible perdue ou une permission refusée déclenche le repli de copie lorsqu’elle réussit. |

## État de la validation

Le [parcours avec un iPhone physique](phase-1-validation.md#reprise-sur-macos-2721) confirme la réception, la classification distante, la persistance et la restitution. La simulation de `.alwaysDeny` couvre le message, la disponibilité de l’historique et la reprise sur une nouvelle copie. Yanis a validé le 15 novembre 2026 le report de l’essai du refus réel sur un environnement macOS qui expose ce réglage.
