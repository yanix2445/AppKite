# Project Brief

## What it is

- AppKite réunit quatre utilitaires natifs dans une app de barre de menus macOS gratuite et sans compte. L’usage personnel précède la diffusion publique.

## Why it exists

- Donner accès aux quatre actions depuis la même app, avec traitement local et fonctionnement hors ligne.

## Domain language

| Terme | Sens dans AppKite |
| --- | --- |
| Space | Bureau virtuel macOS utilisé comme filtre potentiel du switcher. |
| Exclusion | Règle qui écarte une app du traitement d’une feature, par exemple de l’historique ou de la fermeture groupée. |
| Collection | Groupe organisé d’entrées du presse-papiers, aussi appelé pinboard. |

## Ordre de livraison

1. Socle et barre de menus, fusionné dans `main`.
2. Historique du presse-papiers avec recherche, aperçu, épingles, collections et exclusions.
3. Fermeture groupée d’apps avec exceptions, confirmation et option forcée.
4. Switcher de fenêtres individuelles avec miniatures, raccourcis et filtres.
5. Captures et enregistrement d’écran, annotations, OCR et export.
