# Socle et barre de menus

## Target

Permettre à l’utilisateur de lancer AppKite manuellement, d’ouvrir son menu natif depuis la barre de menus macOS et de fermer l’app depuis ce menu.

## Hard constraints

- La barre de menus est le seul point d’entrée visible d’AppKite.
- Le parcours fonctionne sur Apple Silicon sous macOS 26.0 ou ultérieur. Les critères d’acceptation s’appliquent sous macOS 26 et 27.
- Le parcours est utilisable hors ligne, sans compte, avec les autorisations standard de la session macOS.

## Non-goals

- Fonctions de capture, de presse-papiers, de switcher de fenêtres et de fermeture d’autres apps.
- Entrées de menu pour des actions à venir.
- Lancement automatique à l’ouverture de session et écran de réglages.

## Done-when

- Un lancement manuel fait apparaître une seule icône AppKite dans la barre de menus. Cette icône est la seule présence visible de l’app au lancement.
- Un clic sur l’icône ouvre un menu macOS natif dont l’unique action est **Quitter AppKite**.
- Choisir **Quitter AppKite** termine l’application et retire son icône de la barre de menus.
- Relancer AppKite manuellement rétablit l’icône et l’accès à son menu.

## Open Questions

None

## Context

- [Brainstorm approuvé](brainstorm.md)
- [Décisions de plateforme et de sécurité](../../../INSTALL.md#decisions)
