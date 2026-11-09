---
status: approved
---

# Socle et barre de menus

Le socle donne à AppKite un point d’entrée utilisable dès la première version, sur lequel les quatre modules pourront s’ajouter.

## Comportement approuvé

- AppKite se lance manuellement. Au lancement, son icône apparaît dans la barre de menus, qui est son seul point d’entrée.
- Au clic sur l’icône, un menu macOS natif s’ouvre. La seule action du socle est **Quitter AppKite**. Les actions des modules s’ajoutent à mesure qu’elles deviennent utilisables.
- L’action **Quitter AppKite** ferme l’application et son icône disparaît. L’icône revient au prochain lancement.
- Le parcours lancement → clic → fermeture → relance doit fonctionner sous macOS 26 et 27.
