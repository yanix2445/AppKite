---
status: approved
---

# Séparer les responsabilités de l’historique

La refactorisation de `ClipboardHistory` couvre les quatre constats de l’audit d’architecture pour faciliter la maintenance et les tests, en conservant le fonctionnement actuel de l’historique.

## Périmètre approuvé

1. **Collecte et assemblage** : la collecte, l’archivage, l’indexation et le nettoyage ont une responsabilité distincte de l’état affiché. `App` reste responsable de l’assemblage des dépendances.
2. **Collage** : les décisions du cas d’usage deviennent testables indépendamment des effets macOS, en conservant les protections contre une nouvelle copie, le contrôle de la cible et le repli « Copié. Colle avec ⌘V. ».
3. **Chargement des aperçus** : le choix des moteurs de rendu est séparé de la gestion UI des demandes, de leur annulation et du cache.
4. **Structure des cartes** : la zone d’aperçu possède sa propre frontière de vue pour observer l’état de lecture.

## Contrats à préserver

- Les comportements actuels et les données archivées sont conservés.
- L’ordre des copies, les pauses, les exclusions, les protections des cartes, la sélection multiple et les limites du collage groupé restent conformes aux contrats déjà validés.
- La recherche conserve sa cible de premiers résultats sous 200 ms au p95 sur 10 000 entrées mixtes, y compris pendant le rendu des aperçus.

## Validation

- Les corrections sont vérifiées par les tests de régression pertinents, les parcours existants, la compilation et les Previews via Xcode.
- L’accord existant sur macOS 26 reste applicable : compatibilité retenue par hypothèse, vérifications exécutées sur l’hôte disponible. Les dernières validations d’exécution documentées portent sur macOS 27.2.1.

## Références

- [Audit d’architecture et réévaluation Xcode](../2026_11_17_audit/architecture.md)
- [Contrat de l’historique du presse-papiers](../2026_11_09_historique_presse_papiers/spec.md)
- [Contrat des aperçus du presse-papiers](../2026_11_16_apercus_presse_papiers/spec.md)
- [Architecture du projet](../../../memory/architecture.md)
- [Assertions du projet](../../../memory/coding-assertions.md)
