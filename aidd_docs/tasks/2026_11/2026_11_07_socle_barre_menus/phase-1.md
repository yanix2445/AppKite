---
status: done
---

# Instruction: Socle macOS et parcours de la barre de menus

## Architecture projection

> ✅ créer · ✏️ modifier · ❌ retirer

```txt
.
├── AppKite.xcodeproj/
│   └── ✏️ project.xcproj
├── AppKite/
│   ├── ✏️ Info.plist
│   ├── ❌ AppKiteApp.swift
│   ├── ❌ ContentView.swift
│   ├── ❌ Item.swift
│   └── App/
│       ├── ✅ AppKiteApp.swift
│       └── ✅ MenuBarView.swift
├── AppKiteTests/
│   └── ✏️ AppKiteTests.swift
└── AppKiteUITests/
    └── ✏️ AppKiteUITests.swift
```

Le point d’entrée est déplacé dans `App/`. Le MCP `AddInfoPlist` renseigne la clé du bundle à l’emplacement qu’il gère pour la cible, dans le plist ou les réglages du projet.

## Test Scope

| Scenario | Action | Observable outcome | Actor |
| --- | --- | --- | --- |
| Setup | Compiler le schéma `AppKite` pour Mac et ouvrir une session graphique Apple Silicon sur chaque version de macOS prise en charge. | Le bundle est disponible et la zone des icônes de statut est visible. | Xcode et session macOS |
| Happy path | Lancer AppKite, ouvrir le menu de l’icône et choisir **Quitter AppKite**. | Une icône apparaît seule. Le menu natif expose une action. La fermeture termine le processus et retire l’icône. | XCUIAutomation et constat macOS |
| Edge case | Relancer manuellement après la fermeture. | Une seule icône et son menu sont à nouveau accessibles. | XCUIAutomation et constat macOS |
| Edge case | Répéter le parcours hors ligne, sans compte AppKite, avec les autorisations standard de la session. | Le parcours aboutit avec les seules autorisations standard. | Session macOS |
| Teardown | Quitter l’app à la fin du scénario. | Le processus et son icône ont disparu. | XCUIAutomation et session macOS |

## Wireframe

```txt
┌──────────────────────────────────────┐
│ (1) Icône dans la barre de menus      │
├──────────────────────────────────────┤
│ (2) Ligne d’action du menu déroulant │
└──────────────────────────────────────┘
```

1. Icône de statut et point d’entrée du socle.
2. Menu natif à une seule ligne d’action.

## Tasks to do

### `1)` Configurer les trois cibles pour macOS

> Appliquer les décisions de plateforme et de sécurité au projet Xcode.

1. Avec les outils MCP officiels de réglages de cibles, limiter les trois cibles à macOS sur `arm64`, fixer la cible minimale à macOS 26.0 et le mode de langage à Swift 6. Conserver le schéma partagé et le SDK 27.2 de Xcode.
2. Appliquer le réglage App Sandbox désactivé et Hardened Runtime activé pour la cible d’app. Vérifier les réglages effectifs de signature. Le MCP montre que le fichier d’entitlements d’exemple n’est pas raccordé à la cible active.
3. Utiliser `AddInfoPlist` pour déclarer `LSUIElement` comme booléen vrai pour AppKite. Vérifier la clé dans le bundle compilé.

### `2)` Mettre en place la scène de barre de menus

> Donner à AppKite son point d’entrée natif et son action de fermeture.

1. Déplacer le point d’entrée dans `App/` et remplacer la scène d’exemple par une seule `MenuBarExtra` de style `.menu`. Utiliser `AppKite` comme titre accessible et un symbole système provisoire disponible sur macOS 26, proposé `paperplane`.
2. Donner à `MenuBarView` une seule action **Quitter AppKite** et lui injecter depuis le point d’entrée la fermeture normale avec `NSApplication.shared.terminate(nil)`.
3. Retirer les fichiers d’exemple `ContentView.swift` et `Item.swift` après avoir supprimé leurs références au démarrage.

### `3)` Remplacer les tests d’exemple et préparer les preuves de l’assert

> Couvrir le bundle et le parcours natif avec les cibles de test existantes.

1. Remplacer l’exemple Swift Testing par un contrôle du booléen `LSUIElement` dans le bundle de l’app hôte.
2. Remplacer les tests d’exemple XCUIAutomation par le parcours lancement, clic, fermeture et relance. Vérifier la hiérarchie de l’icône sur Mac pour retenir un sélecteur accessible. Attendre les états observables avec les API XCTest. Si XCUIAutomation n’expose pas un élément système, garder le test automatisable et joindre à l’assert un constat manuel explicite pour le geste concerné.
3. Préparer une Preview de l’action avec une fermeture inerte. À l’assert, utiliser le MCP Xcode pour le build, les suites et la capture de cette Preview. Vérifier le menu natif et l’absence d’icône dans le Dock en exécution sous macOS 26 et 27. Exercer le parcours hors ligne, sans compte AppKite, avec les autorisations standard. Si aucun environnement macOS 26 n’est disponible, signaler cette vérification comme restante.

## Test acceptance criteria

| Task | Acceptance criteria |
| --- | --- |
| 1 | Le schéma AppKite compile les trois cibles en Swift 6 pour macOS sur Apple Silicon. Le bundle déclare macOS 26.0 comme minimum et `LSUIElement` vrai. La signature de l’app reflète les réglages de sécurité approuvés. |
| 2 | Au lancement manuel, l’unique présence visible de l’app est une icône dans la barre de menus. Son menu macOS natif contient **Quitter AppKite**. Cette action termine le processus et retire l’icône. |
| 3 | Les suites et la Preview pertinente sont vérifiées via le MCP Xcode. Les résultats d’exécution montrent le parcours complet, dont la relance, sur macOS 26 et 27. Le parcours aboutit aussi hors ligne, sans compte AppKite, avec les autorisations standard. |
