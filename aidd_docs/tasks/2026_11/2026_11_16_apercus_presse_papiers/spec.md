# AppKite · Aperçus du presse-papiers

## Target

Permettre de reconnaître le contenu réel d’une copie dans le bandeau de l’historique, quelle que soit l’app d’origine.

## Hard constraints

- Les aperçus et la lecture fonctionnent hors ligne sur Apple Silicon sous macOS 26 et 27. Les contenus restent sur le Mac.
- Les cartes déjà archivées et les nouvelles cartes sont éligibles. L’aperçu et la lecture restent disponibles après déplacement ou suppression de l’original et après relance d’AppKite, tant que la copie est conservée dans l’historique.
- Les contrôles de lecture ont leur propre action. Un clic sur le reste de la carte et la touche Entrée sur une carte sélectionnée conservent le comportement de collage de l’historique.
- Le chargement des aperçus laisse le bandeau consultable. Les premiers résultats de recherche restent sous 200 ms au p95 sur 10 000 entrées mixtes.

## Non-goals

- Édition des images, documents et médias depuis le bandeau.
- Extension de l’OCR ou de la recherche au contenu des fichiers rangés dans les dossiers.
- Changement des règles de collecte, de conservation, d’exclusion ou de collage de l’historique.

## Done-when

- Une même image copiée depuis une app puis en tant que fichier depuis le Finder montre le même contenu entier dans les deux cartes, avec ses proportions et ses dimensions en pixels. Une image transparente laisse apparaître un damier derrière ses zones transparentes.
- Chaque famille du tableau produit un aperçu du contenu archivé. L’en-tête indique le type et le moment de la copie, avec l’icône de l’app quand l’origine est disponible. Le pied affiche le nom du fichier quand il est connu et les informations utiles à la famille.
- À l’ouverture du bandeau, les GIF, vidéos et pistes audio sont à l’arrêt. Le contrôle dédié lance la lecture dans la carte et permet de la mettre en pause. La fermeture du bandeau arrête la lecture.
- Si AppKite ne peut pas lire le contenu pour l’aperçu, la carte affiche « Aperçu indisponible », avec le nom et le type connus. La carte garde son action de collage.

| Famille | Résultat visible ou audible |
| --- | --- |
| Image, capture et GIF | Image entière et dimensions en pixels. Le bouton Lecture d’un GIF animé lance son animation dans la carte. |
| Vidéo | Image tirée de la vidéo, bouton Lecture au centre, format, taille et durée. La lecture s’effectue dans la carte. |
| Audio ou musique | Pochette du morceau si elle est fournie. Sinon, forme d’onde tirée de l’enregistrement, avec une progression visible pendant la lecture. Le pied affiche le format, la taille et la durée. |
| PDF, DOCX et autres documents compatibles | Miniature de la première page entière, centrée, avec le nom du fichier sous le visuel. |
| CSV et TSV | Grille des premières lignes et colonnes. Une virgule, une tabulation ou un saut de ligne entre guillemets reste dans sa cellule. |
| Dossier ou sélection de fichiers | Mosaïque d’aperçus de quelques éléments de la copie et nombre total d’éléments. Une sélection reste groupée au collage. |

## Open Questions

None

## Context

- [Spécification de l’historique du presse-papiers](../2026_11_09_historique_presse_papiers/spec.md)
- Cadrage et références visuelles validés dans le chat « Aperçus du presse-papiers ».
