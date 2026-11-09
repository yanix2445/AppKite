---
objective: "Rendre AppKite accessible uniquement depuis un menu macOS natif et vérifier le parcours lancement, ouverture, fermeture et relance sur Apple Silicon sous macOS 26 et 27."
status: implemented
---

# Plan: Socle et barre de menus

Source: [Spec validée](./spec.md) et [décisions de plateforme et de sécurité](../../../INSTALL.md#decisions).

## Phases

| # | Phase | File | Depends on |
| --- | --- | --- | --- |
| 1 | Socle macOS et parcours de la barre de menus | [`phase-1.md`](./phase-1.md) | none |

## External sources

| URL | What it settled |
| --- | --- |
| [Apple · MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) | Scène unique pour l’utilitaire, nom accessible de l’icône et rôle de `LSUIElement`. |
| [Apple · Style menu](https://developer.apple.com/documentation/swiftui/menubarextrastyle/menu) | Affichage du contenu sous forme de menu déroulant natif. |
| [Apple · Terminaison de NSApplication](https://developer.apple.com/documentation/appkit/nsapplication/terminate%28_%3A%29) | Fermeture normale de l’application elle-même depuis une action de menu. |
| [Apple · Réglages Xcode](https://developer.apple.com/documentation/xcode/build-settings-reference) | Choix de la plateforme, de l’architecture, de la cible de déploiement et du mode de langage. |
| [Apple · XCUIApplication](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication) | Lancement de l’app de test et observation de la fin du processus. La hiérarchie du menu de statut reste à vérifier en exécution. |

## Impact

| Category | Verdict and evidence | Handled in |
| --- | --- | --- |
| Runtime | Le MCP Xcode expose `My Mac` sur Apple Silicon sous macOS 27.2. L’exécution sous macOS 26 reste non vérifiée. La cible de déploiement et la compilation seules ne prouvent pas ce parcours. | 1 |
| Regression | Risque faible. `AppKiteApp` ouvre la fenêtre et le stockage d’exemple Xcode. Les suites existantes sont des exemples de lancement et de mesure, sans comportement métier à conserver. Les cibles de test sont réutilisées. | 1 |
| Architecture | Le point d’entrée devient une scène de barre de menus dans `App/`. La composition transmet une seule action à la vue. Le stockage quitte le démarrage et reste réservé à la future feature qui en a besoin. | 1 |
| Documentation | Plan et phase dans le dossier de la spec. Les décisions durables sont déjà dans le guide et la mémoire. | 1 |

## Rules

| Rule | Why it applies |
| --- | --- |
| [Architecture](../../../memory/architecture.md) | `App/` compose le socle. Les modules métier restent dans leurs features. |
| [Assert et tests](../../../memory/coding-assertions.md) | Exécuter build, tests et Previews pertinents avec le MCP officiel Xcode à l’assert. |
| [Desktop](../../../memory/desktop.md) | Cible Apple Silicon, Hardened Runtime et décisions App Sandbox approuvées. Les permissions propres aux modules sont demandées à l’usage. |
| [VCS](../../../memory/vcs.md) | L’implémentation et les actions Git attendent leurs validations distinctes. |

## Decisions

| Decision | Why |
| --- | --- |
| Une phase livrable | Les réglages macOS, la scène et le parcours de vérification constituent un même socle observable. |
| Validation sur deux versions | Vérifier la même séquence sous macOS 26 et 27 sur Apple Silicon. L’assert reste incomplet si une version manque. |
