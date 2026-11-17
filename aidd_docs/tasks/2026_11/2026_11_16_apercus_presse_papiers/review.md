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

## Round 3

- Date du 17 novembre 2026.
- Diff de `main` à `96ff00c` vers les changements locaux de `feat/apercus-presse-papiers`, y compris les sources et fixtures ajoutées.
- Axes code, critères d’acceptation et pertinence. Relectures indépendantes des aperçus et de la sélection.
- Verdict **changes-requested** pour quatre défauts hors du corpus des tests actuels.

### Critères

- [x] Les tests d’archives et de rendu couvrent PNG, PDF, DOCX, ODT, CSV, TSV, dossiers et sélections. Les tests d’interface vérifient la lecture de WAV, MOV et GIF depuis l’archive après retrait de l’original. [Validation Xcode](assert.md#round-2)
- [x] ⌘ clic et ⌘ flèches modifient la sélection, ⌫ ouvre la confirmation et la suppression laisse les cartes hors du lot. [Test d’interface](../../../../AppKiteUITests/ClipboardHistoryUITests.swift)
- [x] ⌘A couvre toutes les pages des résultats stabilisés et exclut les cartes épinglées. Dans la recherche, le raccourci sélectionne le texte. [Tests du modèle](../../../../AppKiteTests/ClipboardHistory/ClipboardHistoryPolicyTests.swift) · [Test d’interface](../../../../AppKiteUITests/ClipboardHistoryUITests.swift)
- [ ] ⌘A pendant le chargement applique la sélection aux résultats attendus.
- [x] Un lot de texte est réuni dans l’ordre du bandeau. Les fichiers homonymes gardent des copies de restitution distinctes. [Test d’intégration](../../../../AppKiteTests/ClipboardHistory/ClipboardArchivedHistoryTests.swift)
- [ ] Un tableau borné conserve les lignes complètes et un fichier indisponible laisse la carte utiliser une représentation valide du même élément.
- [x] Les deux Previews se rendent et la recherche reste sous 200 ms au p95 avec les aperçus en charge. [Mesure](assert.md#round-2)

### Constats

1. 🟡 **Le collage groupé prépare tout le volume en une fois.** ⌘A peut cibler l’historique entier. Le stockage prépare toutes les archives, puis le collage de textes conserve les chaînes décodées, leur concaténation et ses octets UTF-8. Un gros lot peut épuiser la mémoire avant d’afficher une erreur. Vérifier le volume cumulé avant le chargement et la duplication, avec un message explicite pour un lot trop grand, ou borner la mémoire par construction. [Sélection](../../../../AppKite/Features/ClipboardHistory/UI/ClipboardHistoryState.swift#L189) · [Restitution](../../../../AppKite/Features/ClipboardHistory/Infrastructure/SwiftDataClipboardHistoryStore.swift#L360) · [Assemblage](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardFormatCodec.swift#L126)
2. 🟡 **⌘A se perd si la recherche charge encore ses résultats.** Un changement de filtre vide la liste, puis le raccourci valide une sélection vide. Quand les résultats arrivent, l’état conserve ce vide. Différer la sélection jusqu’aux résultats de la recherche en cours et abandonner la demande si le filtre change. [Raccourci](../../../../AppKite/Features/ClipboardHistory/UI/ClipboardHistoryView.swift#L124) · [Filtres](../../../../AppKite/Features/ClipboardHistory/UI/ClipboardHistoryState.swift#L564) · [Résultats](../../../../AppKite/Features/ClipboardHistory/UI/ClipboardHistoryState.swift#L657)
3. 🟡 **Un fichier indisponible masque sa représentation lisible.** La branche fichier renvoie immédiatement « Aperçu indisponible », même si le même élément a une représentation PNG ou PDF exploitable. La carte préférait auparavant la vignette de cette représentation. Conserver le résultat du fichier en repli, essayer les représentations archivées et garder le nom du fichier. [Choix du rendu](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L53) · [Affichage](../../../../AppKite/Features/ClipboardHistory/UI/ClipboardHistoryCardView.swift#L113)
4. 🟡 **Un tableau peut perdre une ligne complète à la coupure de lecture.** Si un LF termine la première ligne au 8 192e octet, le décodeur retire ce LF et le parseur écarte la ligne. Une grille vide est alors traitée comme un aperçu réussi et peut aussi masquer une autre représentation. Conserver le séparateur de ligne complet à la coupure et poursuivre les replis quand aucune ligne complète n’a été lue. [Décodage](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardTextDecoding.swift#L28) · [Grille](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L354)

### Limites

- Le volume à partir duquel le collage groupé échoue dépend du contenu et de la mémoire disponible. Le constat porte sur la croissance cumulée du chargement et de l’encodage.
- Les tests couvrent l’exclusion des cartes déjà épinglées au moment de ⌘A. Le comportement d’une carte épinglée ensuite, pendant cette même sélection, reste à préciser.
- La réception d’un collage hétérogène dépend de l’app de destination. Les tests confirment le contenu écrit dans un presse-papiers isolé.
- Le périmètre d’exécution reste macOS 27.2.1. [Validation](assert.md#round-2)

## Round 4

- Date du 17 novembre 2026. Branche `feat/apercus-presse-papiers` à `96ff00c` avec les corrections locales.
- Axes code, critères d’acceptation et pertinence sur les constats du Round 3.
- Verdict **approve**. La contre-revue a identifié le démarrage à froid de l’historique, que le candidat final couvre avec un test dédié.

### Critères

- [x] Les collages groupés sont limités à 4 096 éléments et à 64 Mio de représentations directes. AppKite estime l’espace nécessaire aux copies de fichiers avant de les préparer et donne un message adapté au motif du refus. Le test vérifie qu’un lot refusé préserve les cartes et une restitution précédente. [Stockage](../../../../AppKite/Features/ClipboardHistory/Infrastructure/SwiftDataClipboardHistoryStore.swift#L360) · [Test](../../../../AppKiteTests/ClipboardHistory/ClipboardArchivedHistoryTests.swift#L7)
- [x] ⌘A utilise les résultats disponibles ou attend la première publication quand l’historique est encore vide. Un changement de filtre ou un échec annule la demande. Les deux tests couvrent l’ouverture du stockage, le chargement d’un filtre et le remplacement de la recherche. [Sélection](../../../../AppKite/Features/ClipboardHistory/UI/ClipboardHistoryState.swift#L193) · [Tests](../../../../AppKiteTests/ClipboardHistory/ClipboardHistoryPolicyTests.swift#L238)
- [x] Un fichier illisible peut utiliser une représentation archivée valable en gardant son nom. Le test vérifie aussi la priorité au fichier lorsqu’il est lisible et la conservation des originaux archivés. [Choix du rendu](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardPreviewRenderer.swift#L53) · [Tests](../../../../AppKiteTests/ClipboardHistory/ClipboardPreviewTests.swift)
- [x] Les tableaux gardent les lignes complètes en fin de préfixe, y compris en UTF-16 avec CRLF. Un tableau sans ligne laisse la place à une autre représentation lisible. [Décodage](../../../../AppKite/Features/ClipboardHistory/Infrastructure/ClipboardTextDecoding.swift#L28) · [Tests](../../../../AppKiteTests/ClipboardHistory/ClipboardPreviewTests.swift)
- [x] La suite Xcode, les deux Previews et le p95 sur 10 000 cartes valident le candidat. [Validation](assert.md#round-3)

### Limites

- L’estimation disque emploie les tailles logiques des fichiers et reste conservatrice pour les clones APFS. Un épuisement de l’espace pendant la copie est également traité.
- L’exécution est vérifiée sous macOS 27.2.1. La portée macOS 26 reste celle acceptée dans le [rapport précédent](run.md#périmètre-de-validation-approuvé).
