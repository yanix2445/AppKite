# Exécution du plan de l’historique du presse-papiers

## Run 1

- Head: `385c6f544acc9e40a54336329fa79abe3391cecd`
- Branche `feat/historique-presse-papiers`, avec le code et la documentation de la feature dans le dossier de travail.
- Clôture le 15 novembre 2026 sur macOS 27.2.1, Xcode 27.2 et Apple Silicon.
- Left: revue finale, commit et PR. La validation du refus réel est reportée avec l’accord de Yanis. La compatibilité d’exécution sous macOS 26 reste une hypothèse déjà acceptée.
- Le MCP Xcode a compilé le schéma AppKite, exécuté 55 tests, dont 5 d’interface, et rendu trois aperçus. [Assert de clôture](assert.md#round-9).

| Task | Validation | Result |
| --- | --- | --- |
| 1.1 | Cycle du menu, fermeture et relance via `RunAllTests`. | Une seule icône, les actions attendues et un menu accessible après relance. |
| 1.2 | Tests Swift de collecte, déduplication et persistance, puis sondes de refus et Handoff. [Phase 1](phase-1-validation.md#reprise-sur-macos-2721). | La première nouvelle copie est conservée, les doublons remontent et la copie de l’iPhone est reconnue comme distante. Le refus et la reprise sont exercés par simulation. |
| 1.3 | Tests d’ouverture par menu et raccourci, sonde de conflit et géométrie du panneau. [Assert Round 7](assert.md#round-7). | Le bandeau s’ouvre par les deux accès. En cas de conflit, la combinaison précédente est conservée. La sonde observe le panneau au bas de l’écran, au-dessus du Dock. |
| 1.4 | Sonde de collage entre deux apps, presse-papiers de test et `ClipboardRoundTripTests`. [Phase 1](phase-1-validation.md). | Le texte est inséré dans la cible et reste disponible au second collage. Le repli restitue le contenu et une copie intervenue entre-temps est préservée. |
| 2.1 | `ClipboardOrganizationTests` et test d’interface de création et suppression de collection. | Les épingles, les appartenances multiples et les règles de protection persistent. |
| 2.2 | `ClipboardHistoryPolicyTests` sur les pauses et la collecte pendant une écriture en cours. | Les pauses persistent après relance. Les reprises manuelle et programmée écartent les copies manquées pendant la pause. |
| 2.3 | `ClipboardHistoryPolicyTests` et `ClipboardFormatTests` avec origines et marqueurs simulés. | Les exclusions d’application et le réglage des copies confidentielles s’appliquent indépendamment. |
| 3.1 | `ClipboardFormatTests` et collage de cellules dans Numbers. [Phase 3](phase-3.md#état-de-la-validation). | Les neuf familles sont exercées. Numbers conserve les formules et le format disponibles. Les tests couvrent les replis TSV et CSV. |
| 3.2 | `ClipboardArchiveTests` et `ClipboardArchivedHistoryTests` sur les sélections Finder. | Les sélections archivées se recollent après retrait de l’original. Un élément indisponible fait écarter toute la sélection. |
| 3.3 | Pression disque et interruptions de processus sur des volumes APFS isolés. [Assert Round 6](assert.md#round-6). | Une seule carte éligible est évincée quand elle suffit. Les copies refusées préservent l’historique. La relance élimine les archives orphelines. |
| 4.1 | `ClipboardTextExtractorTests` et `ClipboardSearchTests`. | Texte, URL, noms de dossiers et OCR d’images et de PDF sont retrouvables. L’index suit la persistance, la recopie et la suppression. |
| 4.2 | `ClipboardSearchTests` et test d’interface de recherche et filtre par type. | Les filtres se combinent, y compris pour les épingles. Le bandeau présente uniquement les cartes correspondantes. |
| 4.3 | Mesure à l’écran sur 10 000 cartes avec ScreenCaptureKit. [Assert Round 8](assert.md#round-8). | p95 de 90,50 ms au repos et 106,16 ms pendant l’archivage. Les mesures couvrent la mise à jour du champ jusqu’à l’apparition des résultats. |
