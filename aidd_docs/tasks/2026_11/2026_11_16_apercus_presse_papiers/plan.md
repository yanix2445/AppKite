---
objective: "Afficher et lire dans le bandeau un aperçu fidèle des copies archivées, quelle que soit leur origine, tout en conservant le parcours de collage et le temps de réponse de la recherche."
status: reviewed
---

# Plan: Aperçus du presse-papiers AppKite

Source: [Spec validée](./spec.md)

La validation d’exécution de ce chantier repose sur macOS 27.2.1. Le 16 novembre 2026, Yanis a accepté de retenir la compatibilité macOS 26 par hypothèse pour poursuivre la revue. [Rapport de validation](./run.md#périmètre-de-validation-approuvé)

## Phases

| # | Phase | File | Depends on |
| --- | --- | --- | --- |
| 1 | Copies archivées et images | [`phase-1.md`](./phase-1.md) | none |
| 2 | Documents, tableaux et dossiers | [`phase-2.md`](./phase-2.md) | 1 |
| 3 | Vignettes vidéo et audio | [`phase-3.md`](./phase-3.md) | 1, 2 |
| 4 | Lecture dans la carte et validation intégrée | [`phase-4.md`](./phase-4.md) | 1, 2, 3 |

## External sources

| URL | What it settled |
| --- | --- |
| [Apple · Image I/O](https://developer.apple.com/documentation/imageio/cgimagesource) | Charger à partir d’octets ou d’une URL locale, lire les dimensions et l’orientation et créer une image à taille bornée. Documentation Xcode consultée pour l’animation GIF. |
| [Apple · Quick Look Thumbnailing](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator/request/representationtypes-swift.struct) | Demander une vignette de contenu. Le type icône est distinct. Le rendu réel du DOCX hors ligne sur les deux macOS reste à vérifier. |
| [Apple · Image I/O pour les pages PDF](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)) | Image I/O peut rasteriser une page PDF à un index donné. La phase 2 vérifie le cadrage de la page avec les fichiers et représentations PDF. |
| [Apple · Image de vidéo](https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset) | Décodage asynchrone d’une image de vidéo avec taille maximale et transformation de la piste. |
| [Apple · Lecture d’échantillons audio](https://developer.apple.com/documentation/avfoundation/avassetreadertrackoutput) | Lecture de PCM pour calculer des amplitudes à partir du son réel, sans garder le flux entier en mémoire. |
| [Apple · Lecture de média](https://developer.apple.com/documentation/avfoundation/avplayer) | Lecture, pause et observation du temps d’un média local. La phase 4 vérifie la suppression de l’observateur et l’arrêt à la fermeture. |

## Impact

| Category | Verdict and evidence | Handled in |
| --- | --- | --- |
| Runtime | Le bandeau existe et tourne sous macOS 27.2.1. Les rendus DOCX hors ligne et plusieurs codecs restent à vérifier en situation réelle. La disponibilité d’un Mac ou d’une VM macOS 26 est un prérequis de validation à confirmer dès la phase 1. | 1 à 4 |
| Regression | Risque élevé pour le collage, la recherche et le focus clavier. Les cartes sont aujourd’hui entièrement des boutons de collage, et le chargement des vignettes suit le lot de recherche. Les suites d’archives et les parcours XCTest fournissent le filet de départ. | 1 et 4 |
| Architecture | Certaines représentations image/PDF ont déjà une vignette. Le lecteur d’archive valide le manifeste puis charge les représentations ou crée une copie destinée au collage. La nouvelle lecture d’aperçu a besoin d’un accès ciblé à l’archive et d’une durée de vie indépendante du collage. | 1 à 4 |
| Documentation | La spec validée sert de contrat. La validation consignera le corpus exercé, les versions macOS, les mesures et les limites éventuelles. | 4 |

## Rules

| Rule | Why it applies |
| --- | --- |
| [Architecture AppKite](../../../memory/architecture.md) | Conserver les responsabilités dans la feature. Garder le décodage et les accès disque hors de l’acteur principal. |
| [Assertions AppKite](../../../memory/coding-assertions.md) | Consulter la documentation Apple via Xcode, garder des ressources de test propres à AppKite et exécuter BuildProject, les tests du schéma et les aperçus pertinents. |
| [Tests AppKite](../../../memory/testing.md) | Swift Testing pour le stockage et les décodeurs. XCTest pour les actions dans le bandeau. Exercer macOS 26 et 27. |
| [VCS AppKite](../../../memory/vcs.md) | Les corrections de l’audit précédent sont dans le diff local de `fix/qualite-historique-presse-papiers`. Identifier leur état de référence avant l’implémentation pour isoler les deux diffs. Chaque commit, push ou PR demande le feu vert prévu par le projet. |

## Decisions

| Decision | Why |
| --- | --- |
| Repartir de l’archive originale par identifiant de carte. | Les cartes existantes peuvent acquérir un aperçu sans recopier l’original et sans dépendre des fichiers temporaires de collage. |
| Maintenir les catégories et représentations historiques. Exposer la nature du contenu dans un modèle d’aperçu séparé. | Les filtres, les empreintes, les données de collage et le schéma d’archive gardent leur contrat. |
| Générer après publication des résultats, à la demande et avec un cache mémoire borné. | La recherche reste indépendante des décodeurs et la réouverture d’une ancienne base ne déclenche pas de balayage synchrone. Une carte visible peut retrouver son aperçu après relance depuis sa copie archivée. |
| Donner une seule session de lecture au bandeau. | Lancer un deuxième média arrête le premier. Les chemins de fermeture et de changement de carte peuvent libérer le lecteur de façon prévisible. |
