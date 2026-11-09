# Database

## Setup

- SwiftData est retenu pour l’historique et les métadonnées de `ClipboardHistory`. Les contenus volumineux utilisent des fichiers locaux.
- Le schéma de l’historique sera défini par la spec de `ClipboardHistory`.

## Conventions

- Garder les modèles SwiftData et leur contexte dans l’adaptateur de stockage de la feature. Les cas d’usage reçoivent des valeurs Swift qui décrivent leurs besoins, par exemple les métadonnées nécessaires à l’affichage.
- Préserver le fonctionnement hors ligne lors des décisions de persistance et de partage.
