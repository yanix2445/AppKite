# Revue des aperçus du presse-papiers

## Round 1

- Date du 16 novembre 2026.
- Branche `feat/apercus-presse-papiers` à `062fc3b`, avec les modifications locales et les fichiers ajoutés. La sauvegarde d’audit `bdd35fe` sert de référence pour isoler le diff des aperçus.
- Axes code, critères d’acceptation et pertinence.
- Verdict **changes-requested**. Le choix des représentations peut masquer un aperçu lisible ou une animation. Le routage documentaire écarte aussi des formats déclarés par Quick Look.

### Critères

- [x] Les tests isolent le presse-papiers et le stockage, y compris après relance. [Fixture XCTest](../../../../AppKiteUITests/IsolatedAppKite.swift#L11)
- [x] Le PNG direct ou archivé garde ses proportions et ses dimensions après suppression de l’original. La recherche reste réactive pendant le rendu sur le corpus mesuré. [Validation](run.md#run-1)
- [x] Le corpus PDF et DOCX rend une première page sous macOS 27.2.1. L’état indisponible est couvert pour un fichier sans rendu. [Tests](../../../../AppKiteTests/ClipboardHistory/ClipboardPreviewTests.swift#L66)
- [x] Les grilles des fichiers et des valeurs copiées préservent les séparateurs entre guillemets. [Tests](../../../../AppKiteTests/ClipboardHistory/ClipboardPreviewTests.swift#L123)
- [x] La mosaïque garde le compteur du dossier et l’ordre de la sélection. [Tests](../../../../AppKiteTests/ClipboardHistory/ClipboardPreviewTests.swift#L152) · [Restitution de l’historique](../2026_11_09_historique_presse_papiers/spec.md)
- [ ] Les représentations disponibles donnent un aperçu cohérent quelle que soit l’app source. L’ordre des représentations d’un même élément peut masquer un PNG valide ou la lecture du GIF.
- [x] Les fixtures vidéo et audio montrent un photogramme, une pochette ou les amplitudes de l’enregistrement. [Validation](run.md#run-1)
- Vérification en exécution encore ouverte pour la lecture du MOV et du GIF après la suppression de l’original et la relance. Le parcours complet couvre un WAV, la lecture GIF est exercée séparément et la vidéo est couverte pour le rendu de sa vignette. [Parcours audio](../../../../AppKiteUITests/ClipboardHistoryUITests.swift#L90) · [Lecteur GIF](../../../../AppKiteTests/ClipboardHistory/ClipboardPlaybackTests.swift#L12) · [Vignette vidéo](../../../../AppKiteTests/ClipboardHistory/ClipboardMediaPreviewTests.swift#L78)
- [x] Le p95 reste sous 200 ms sur 10 000 entrées et les deux Previews se rendent sur macOS 27.2.1. La compatibilité d’exécution macOS 26 est retenue par hypothèse avec l’accord de Yanis. [Validation](run.md)

### Constats

- 🟡 **Un média illisible masque une image lisible du même élément.** Le moteur média renvoie un résultat `.unavailable` lorsque le conteneur ne s’ouvre pas. Le sélecteur le retourne immédiatement, avant de lire les représentations visuelles. Une copie directe avec un MOV illisible et un PNG valide perd donc sa miniature. Conserver le résultat indisponible comme repli et poursuivre la recherche d’un aperçu utilisable. [Sélection](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L61) · [Retour du moteur média](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardMediaPreview.swift#L40)
- 🟡 **Un PNG de repli peut faire perdre la lecture d’un GIF animé.** L’archive conserve l’ordre des représentations. Le moteur garde la première image décodable et le bouton de lecture dépend des métadonnées du GIF. Une copie contenant d’abord un PNG, puis le GIF animé, reste figée. Donner priorité à la représentation animée lisible et conserver le PNG comme repli. [Ordre à la capture](../../../../AppKite/Features/ClipboardHistory/Infrastructure/PasteboardClient.swift#L157) · [Sélection d’image](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L96) · [Détection GIF](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L246)
- 🟡 **Des documents compatibles avec Quick Look sont écartés avant la demande de vignette.** Après le décodage natif, seuls les formats de la liste interne et le texte brut atteignent Quick Look. L’inventaire de ce Mac associe par exemple OpenDocument à un générateur système, et `odt` est absent de la liste. Étendre le routage documentaire aux formats compatibles, puis vérifier un rendu de contenu avec une fixture ODT locale. [Formats déclarés](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L20) · [Routage](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L163)

### Limites

- La revue est statique. Les sources et tests correspondent à l’état validé dans le rapport, qui consigne 89 réussites sous macOS 27.2.1.
- L’inventaire Quick Look établit la présence d’un générateur ODT. Un essai avec une fixture doit confirmer la représentation de type vignette.
- Le plan prévoit d’intégrer les corrections d’audit avant la PR des aperçus. Le présent verdict porte sur les aperçus. [Phase 1](phase-1.md#tasks-to-do)

## Round 2

- Date du 16 novembre 2026.
- Branche `feat/apercus-presse-papiers` à `062fc3b` avec les corrections locales.
- Contre-revue sur les trois constats du Round 1 et la lecture après relance.
- Verdict **approve** pour les corrections revues sur macOS 27.2.1. La suite complète passe avec 93 tests, dont 8 d’interface. [Validation](run.md#run-2--corrections-de-la-revue)

| Constat | Correction vérifiée |
| --- | --- |
| Vidéo illisible et PNG valide | Le résultat média indisponible reste en repli pendant la recherche d’une représentation visuelle. Le test archive un MOV illisible avec un PNG et retrouve les dimensions du PNG. [Sélection](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L70) · [Test](../../../../AppKiteTests/ClipboardHistory/ClipboardPreviewTests.swift#L66) |
| PNG et GIF animé | Le GIF est essayé avant les images statiques de repli. Les deux cas testent un GIF lisible puis illisible. [Sélection](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L113) · [Tests](../../../../AppKiteTests/ClipboardHistory/ClipboardPreviewTests.swift#L93) |
| ODT écarté de Quick Look | Le routage accepte les types de documents composites. L’ODT et le DOCX de test rendent une page. Les types inconnus conservent l’état d’indisponibilité. [Routage](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L173) · [Tests](../../../../AppKiteTests/ClipboardHistory/ClipboardPreviewTests.swift#L149) |
| Lecture après relance | Les nouveaux parcours retirent les originaux GIF et MOV, relancent AppKite et vérifient la lecture complète dans la carte. [Parcours](../../../../AppKiteUITests/ClipboardHistoryUITests.swift#L124) |

Les vues Xcode large et compacte ont été rendues dans le projet AppKite. La compatibilité d’exécution sur macOS 26 reste retenue par hypothèse. [Périmètre approuvé](run.md#périmètre-de-validation-approuvé)
