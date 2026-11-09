# Assert · Socle et barre de menus

## Périmètre approuvé

- Décision du 9 novembre 2026, accord explicite `go 27`. L’assert du socle est réalisé sur le Mac Apple Silicon hôte, sous macOS 27.2.
- La cible minimale reste macOS 26.0. Le parcours réel sous macOS 26 est reporté à la validation avant diffusion publique.
- Cette décision ajuste le périmètre de validation de la phase pour cet assert. La [spec validée](spec.md) conserve le contrat de compatibilité.

## Résultats sur macOS 27.2

| Vérification | Résultat |
| --- | --- |
| Build via `BuildProject` | Schéma `AppKite` et cibles de test compilés avec succès. |
| Tests via `RunAllTests` | 2 réussites sur 2. `hostAppIsMenuBarOnly()` contrôle le bundle et `testMenuBarLaunchQuitAndRelaunch()` exerce le menu natif. |
| Preview via `RenderPreview` | [Action du menu](preview-menu-macos27.png) rendue sur le Mac hôte. Cette capture montre la vue de l’action. |
| Parcours hors ligne | Deux lancements successifs avec le réseau bloqué pour le processus AppKite. À chaque lancement, une icône de statut, aucune fenêtre et une politique d’activation `.accessory` (absence du Dock). Le menu expose uniquement « Quitter AppKite ». L’action termine le processus avec le code `0` et retire l’icône. |
| Plateforme et sécurité | Trois cibles configurées en `arm64`, Swift 6 et macOS 26.0 minimum. Le bundle compilé confirme `arm64`, macOS 26.0 minimum et `LSUIElement = true`. App Sandbox désactivé dans la configuration et Hardened Runtime confirmé par la signature du bundle. |

Le contrôle hors ligne a utilisé une règle temporaire du système qui refusait les connexions du processus lancé. Le refus a été vérifié avec une connexion de contrôle. L’autorisation Accessibilité utilisée pour observer le menu appartenait à la sonde de vérification.

## Verdict

Assert réussi dans le périmètre approuvé sur macOS 27.2 après le second passage des vérifications. Aucune correction de code pendant cette étape.

La validation en exécution sous macOS 26 reste requise avant diffusion publique.

## Nouvel assert après la reprise du 9 novembre 2026

| Vérification | Résultat sur macOS 27.2 |
| --- | --- |
| Build, tests et Preview | Deux passages réussis via le MCP Xcode, avec 2 tests sur 2 à chaque passage. La capture finale est identique octet pour octet à la [Preview conservée](preview-menu-macos27.png). |
| Parcours hors ligne | Deux lancements réussis à chaque passage avec le réseau bloqué pour AppKite. Une icône de statut, aucune fenêtre, politique `.accessory`, une seule action de menu et retrait de l’icône à la fermeture. |
| Bundle compilé | `arm64`, macOS 26.0 minimum, `LSUIElement = true` et signature avec Hardened Runtime. |
| Mémoire AIDD | Les liens locaux des fiches [carte du code](../../../memory/codebase-map.md) et [stockage](../../../memory/database.md) ont été vérifiés après correction. |

**Avertissement d’exécution.** Les deux passages de `RunAllTests` signalent « This method should not be called on the main thread » dans le test d’interface, qui réussit. Le journal macOS du passage final, à 06 h 01, attribue le diagnostic au contrôle de confiance du framework Apple `Security` dans le processus AppKite, au lancement et à la relance. Les essais en implémentation ont également produit le diagnostic avant le comptage des icônes. L’appel déclencheur reste à identifier.

**Verdict.** Les vérifications du périmètre macOS 27.2 passent. L’avertissement reste ouvert pour la nouvelle revue.
