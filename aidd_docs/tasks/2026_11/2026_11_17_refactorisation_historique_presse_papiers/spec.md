# AppKite · Séparer les responsabilités de l’historique

## Target

Rendre la collecte, les décisions de collage et le chargement des aperçus vérifiables indépendamment de leur présentation et de leurs effets système, avec une observation de la lecture limitée à la zone d’aperçu des cartes.

## Hard constraints

- Les comportements définis par les contrats validés de l’historique et des aperçus sont conservés : ordre des copies, pauses et reprises, exclusions et confidentialité, épingles et collections, protection et nettoyage des cartes, recherche et filtres, sélection multiple, collage et lecture des médias.
- Les cartes et leurs contenus déjà archivés restent accessibles après relance et après suppression des originaux. Les limites existantes du collage groupé, ses refus et la préservation d’une restitution précédente sont maintenus.
- Le choix et l’assemblage des dépendances restent distincts des responsabilités d’affichage. Les contrôles de cible et de changement du presse-papiers, le repli « Copié. Colle avec ⌘V. », l’annulation des aperçus et les bornes existantes de concurrence et de cache sont préservés.
- Les premiers résultats de recherche restent sous 200 ms au p95 sur 10 000 entrées mixtes, au repos et pendant le rendu des aperçus.
- Le fonctionnement reste local, hors ligne et destiné à Apple Silicon sous macOS 26 ou ultérieur. Le périmètre de validation déjà accepté s’applique : exécution sur l’hôte disponible, compatibilité macOS 26 retenue par hypothèse.

## Non-goals

- Ajouter des fonctionnalités, étendre les formats reconnus ou modifier l’apparence du bandeau.
- Modifier les contrats de collecte, de conservation, de collage ou de lecture déjà validés.

## Done-when

1. Le cycle de collecte, d’archivage, d’indexation et de nettoyage peut être exercé sans instancier l’état d’interface. Cet état conserve les responsabilités de présentation, de sélection et de commande du bandeau ; il ne choisit plus les implémentations des traitements de fond. Les scénarios existants de copies pendant un archivage, de pause et de nettoyage coordonné au collage gardent leurs résultats.
2. Les décisions de collage peuvent être vérifiées avec des résultats contrôlés pour l’écriture et l’envoi, sans modifier le presse-papiers réel, déplacer le focus ou envoyer d’événement à une app. Les scénarios distinguent l’envoi réussi, l’envoi indisponible avec copie de repli, l’échec d’écriture et une nouvelle copie intervenue avant l’envoi, conformément au contrat existant.
3. Un chargement d’aperçu peut fournir un résultat contrôlé sans appeler les moteurs réels ni modifier la gestion des cartes visibles, de la file, de l’annulation et du cache. Les demandes devenues inutiles ne publient pas de résultat périmé, et une fermeture ou une disparition de carte conserve le comportement d’arrêt prévu.
4. La dépendance observable à l’état de lecture appartient à la zone d’aperçu plutôt qu’à la carte entière. L’en-tête et le pied n’observent pas cet état pour construire leur contenu. Les contrôles de lecture, les actions de collage et l’apparence des cartes conservent leur comportement.

## Open Questions

None

## Context

- [Cadrage approuvé](brainstorm.md)
- [Quatre constats de l’audit d’architecture](../2026_11_17_audit/architecture.md)
- [Contrat de l’historique du presse-papiers](../2026_11_09_historique_presse_papiers/spec.md)
- [Contrat des aperçus du presse-papiers](../2026_11_16_apercus_presse_papiers/spec.md)
- [Architecture du projet](../../../memory/architecture.md)
- [Assertions du projet](../../../memory/coding-assertions.md)
- [Stratégie de tests](../../../memory/testing.md)
- [Dernière validation complète documentée](../2026_11_16_apercus_presse_papiers/assert.md#round-3)
- [Périmètre macOS accepté](../2026_11_16_apercus_presse_papiers/run.md#périmètre-de-validation-approuvé)
