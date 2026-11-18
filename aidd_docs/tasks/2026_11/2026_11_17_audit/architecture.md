# Audit d’architecture · Historique du presse-papiers

Les frontières du domaine et de la persistance sont préservées. L’écart principal se situe dans l’état d’interface, qui assemble des adaptateurs et pilote les traitements de fond de la fonctionnalité.

- **Date** — 17 novembre 2026.
- **Périmètre** — `AppKite/Features/ClipboardHistory`, avec lecture de l’assemblage dans `App` et des tests utiles aux constats. Sources de `main` à `3d5542222558989280f9a5862b9826cf043ff346` ; copie de travail propre avant l’audit.
- **État** — `good` selon le barème AIDD : aucun constat critique. Cela ne signifie pas une absence de dette architecturale.
- **Constats après réévaluation Xcode** — 0 critique, 2 majeurs et 2 mineurs.
- **Référentiel** — [Architecture](../../../memory/architecture.md#key-decisions) et [guide technique](../../../INSTALL.md#architecture) : `App` assemble les dépendances, `UI` appelle `UseCases`, `Infrastructure` implémente les contrats de ces cas d’usage. Les couches partagent volontairement une cible Xcode.

## Findings

Les chemins ci-dessous sont relatifs à la racine du dépôt. Effort indicatif : `S` = moins d’une heure, `M` = moins d’une journée, `L` = plus d’une journée.

| Gravité | Catégorie | Emplacement | Constat | Correction proposée | Effort |
| --- | --- | --- | --- | --- | --- |
| 🟡 Majeur | architecture | `AppKite/Features/ClipboardHistory/UI/ClipboardHistoryState.swift:423` | **1. L’état d’interface porte le cycle de collecte et l’assemblage du stockage.** Il ouvre directement `SwiftDataClipboardHistoryStore`, gère la boucle de surveillance, la file d’archivage, le nettoyage des restitutions et la relance de l’indexation. Ces traitements ont le même propriétaire que la sélection, les filtres et la présentation du bandeau. Modifier le cycle de collecte impose donc de modifier et d’instancier l’état d’interface ; les règles de pause et d’exclusion sont également exercées via cet état dans les tests. | Extraire un service de collecte de la feature, responsable de la surveillance, de l’archivage, de l’indexation et de leur coordination avec le collage. Le construire avec le stockage et les adaptateurs dans `App`. Garder dans l’état les données affichées, la sélection et les commandes de présentation. Préserver l’ordre des copies, les exclusions et la coordination du nettoyage. | M |
| 🟡 Majeur | architecture | `AppKite/Features/ClipboardHistory/UseCases/PasteClipboardEntry.swift:12` | **2. Le cas d’usage de collage dépend des implémentations d’Infrastructure.** Ses dépendances sont les classes concrètes `PasteboardClient` et `AppKitPasteTarget`, et ses paramètres exposent `NSRunningApplication`. Le sens de dépendance documenté est inversé. L’envoi du collage ne peut pas être remplacé par un substitut avec cette interface ; les décisions du cas d’usage restent liées à l’adaptateur qui contrôle les permissions, le focus et les événements macOS. | Déclarer dans `UseCases` les opérations nécessaires à l’écriture conditionnelle et à l’envoi du collage, sous forme de contrats ou de closures. Capturer la cible AppKit à la frontière de l’adaptateur et assembler ces opérations dans `App`. Conserver les contrôles du compteur, de l’annulation et le repli sur la copie. | M |
| 🟢 Mineur | architecture | `AppKite/Features/ClipboardHistory/UI/ClipboardPreviewRequests.swift:89` | **3. La file d’aperçus UI choisit directement les moteurs de rendu.** Elle lit l’archive via le contrat de stockage, puis lance `ClipboardPreviewRenderer` avec `ClipboardMediaPreview.render`. Le cache et la visibilité des cartes sont ainsi couplés aux implémentations de conversion des archives. Remplacer le rendu par un résultat contrôlé exige de modifier cette classe ou de passer par les moteurs réels. | Injecter une opération de chargement d’aperçu, assemblée avec le stockage et les moteurs dans `App`. Garder dans `ClipboardPreviewRequests` la visibilité, la file, l’annulation des demandes et le cache. Définir explicitement qui transmet l’annulation au rendu. | S |
| 🟢 Mineur | architecture | `AppKite/Features/ClipboardHistory/UI/ClipboardHistoryCardView.swift:114` | **4. La zone d’aperçu ne possède pas sa propre frontière de vue.** `header`, `preview` et `footer` sont des propriétés calculées évaluées par le même `body`. La lecture de `playback.activeID` dans `preview` est donc observée par la carte entière. Un changement de lecture réévalue aussi la construction de l’en-tête et du pied de carte. La guidance SwiftUI d’Apple recommande une `struct View` distincte pour une section avec sa propre dépendance observable. | Extraire au minimum la zone d’aperçu dans une sous-vue avec ses données et la référence stable de lecture. Effectuer la lecture de `activeID` dans cette sous-vue. Préserver le rendu et l’identité des cartes. | S |

### Éléments de preuve et portée

- **Constat 1** — L’ouverture concrète du stockage est aux lignes 423–426 de `ClipboardHistoryState.swift`. La file de collecte et sa surveillance sont aux lignes 439–469, le nettoyage aux lignes 493–525 et la boucle d’indexation aux lignes 701–726. `AppKiteApp.swift:34` délègue actuellement l’assemblage au constructeur par défaut de l’état. `ClipboardHistoryPolicyTests.swift:8` et `:136` passent par cet état pour les règles de pause et l’ordre de collecte. L’ouverture du stockage est déjà injectable et des substituts de stockage existent : le constat porte sur le propriétaire des traitements, pas sur une impossibilité de les tester.
- **Constat 2** — `AppKitPasteTarget.swift:22` vérifie ou demande l’accès aux événements ; les lignes 27–45 restaurent le focus puis envoient les événements. Les tests lus dans `ClipboardRoundTripTests.swift:74` et `:114` construisent les adaptateurs réels avec une cible `nil` et vérifient le compteur et la copie de repli. Ils ne fournissent pas de substitut pour l’envoi. Ce constat n’affirme pas une absence de toute couverture d’intégration ailleurs.
- **Constat 3** — Le stockage est lu à `ClipboardPreviewRequests.swift:91`, les moteurs sont fixés aux lignes 95–96 et l’annulation du rendu est relayée aux lignes 98–102. La séparation proposée concerne ce choix d’implémentation ; la gestion des aperçus visibles et du cache appartient bien à l’UI.
- **Constat 4** — `ClipboardHistoryCardView.swift:18` compose les trois sections via des helpers ; la lecture de `activeID` est à la ligne 116. Le nouveau constat concerne cette frontière d’observation, pas une lenteur mesurée. `activeID` change lors des transitions de lecture, pas à chaque image. Les valeurs fréquentes de progression et de trame sont déjà lues dans `ClipboardArchivedPreviewView`.

### Réévaluation avec Intégration Xcode

Le 17 novembre 2026, le même état source a été réexaminé avec le plugin `xcode-integration@agent-toolkit`, son skill officiel Apple `swiftui-specialist` et les outils du serveur déclaré par le plugin. Les outils n’étant pas exposés directement dans ce chat, ils ont été appelés par JSON-RPC via son pont officiel `xcrun mcpbridge`, avec le client local déjà présent dans `build/validation/xcode-mcp-call.py`.

| Contrôle effectué | Résultat observé |
| --- | --- |
| Découverte du serveur puis `XcodeOpenWorkspace` | 54 outils disponibles ; projet AppKite existant ouvert, schéma `AppKite`, destination `My Mac`. |
| `XcodeListTargets` | Une cible d’application et deux cibles de test. |
| `GetTargetBuildSettings` | L’isolation par défaut sur l’acteur principal est configurée pour la cible de l’app. L’absence d’annotation explicite sur `ClipboardHistoryState` n’est donc pas retenue comme défaut. |
| `XcodeRead` | Ouverture concrète du stockage et orchestration de la collecte relues dans le projet actif. |
| `DocumentationSearch` | Documentation Apple sur les dépendances d’observation d’un modèle et les propriétés effectivement lues par les vues. |
| `BuildProject` avec `buildForTesting: true` | Compilation réussie en 5,953 secondes, aucune erreur remontée. Les tests n’ont pas été exécutés. |
| `GetBuildLog`, filtre `warning` | Aucun avertissement ou erreur dans le journal de cette compilation. |
| `XcodeRefreshCodeIssuesInFile` | Zéro diagnostic dans chacun des quatre fichiers : `ClipboardHistoryState`, `PasteClipboardEntry`, `ClipboardPreviewRequests` et `ClipboardHistoryCardView`. |

Les réponses brutes et le journal de compilation sont conservés dans `build/validation/audit-xcode.yqf9nc0k/`. Ces contrôles établissent la compilation et les diagnostics du candidat ; ils ne constituent pas un test de ses parcours utilisateur ni une détection automatique des écarts architecturaux.

**Sources Apple utilisées** : skill `swiftui-specialist` du plugin installé `1.0.0+codex.20261112073545`, références `structure.md` (« Always use separate View types for sections, not computed properties ») et `dataflow.md` (« Model objects with @Observable », « Per-property dependency granularity », « Multiple individual @Observable property reads are fine »). La documentation [Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app#Observe-model-data-in-a-view) a également été consultée via `DocumentationSearch`.

**Nuance du premier audit** : Apple accepte un modèle `@Observable` partagé qui charge des données et porte de la logique. Il n’impose pas la Clean Architecture d’AppKite. Les constats 1 à 3 restent des écarts à la séparation retenue par le projet, pas des interdictions SwiftUI. L’observation est granulaire par propriété ; le nombre de propriétés de l’état ne démontre pas une invalidation globale. Commencer le constat 1 par l’injection du stockage depuis `App` permet une première correction limitée avant une éventuelle extraction plus large de la collecte.

### Points conformes

- Les modèles de `Domain` utilisent Swift et Foundation, sans dépendance observée vers `UI` ou `Infrastructure`.
- `RecordClipboard`, `SearchClipboardHistory` et `ManageClipboardHistory` s’appuient sur `ClipboardHistoryStore`, déclaré dans `UseCases`.
- Les modèles SwiftData, leur contexte, les transactions et l’index restent dans l’adaptateur de persistance. Le contrat de stockage expose des valeurs de la feature.
- `ClipboardArchive` reste cohérent autour du format et du cycle de vie des copies persistées : empreinte, préparation, publication, lecture, réconciliation et restitutions utilisent le même manifeste et les mêmes chemins. Ses 757 lignes ne démontrent pas, seules, une responsabilité mal placée. Aucun découpage architectural obligatoire n’est retenu pour ce fichier.
- Les 841 lignes de `ClipboardHistoryState.swift` comprennent 112 lignes de fixtures d’aperçu sous `#if DEBUG`. Le constat 1 repose sur les responsabilités et les dépendances de production, pas sur ce total.
- L’usage d’AppKit pour les panneaux, le focus et la lecture multimédia de l’interface est compatible avec le guide. Il n’est pas considéré comme une violation en soi.
- Une cible Xcode et un processus sont des décisions explicites. L’audit ne recommande ni nouveau module compilé ni service XPC.

## Top actions

1. **Séparer la collecte de l’état du bandeau** (constat 1), via `aidd-dev:07-refactor`. Commencer par déplacer l’assemblage dans `App`, puis extraire le cycle de collecte sans changer son ordre d’exécution. Vérifier les pauses, exclusions, copies pendant un archivage lent, relances de l’indexation et nettoyages concurrents avec le collage.
2. **Rendre les effets du collage substituables** (constat 2), via `aidd-dev:07-refactor`. Ajouter avec `aidd-dev:06-test` des scénarios déterministes d’envoi réussi, refusé ou interrompu par une nouvelle copie ; conserver les tests d’intégration des adaptateurs macOS.
3. **Injecter le chargement des aperçus** (constat 3) lorsque cette frontière sera modifiée. Préserver la concurrence bornée, le cache et l’annulation ; éviter un découpage supplémentaire de chaque moteur sans besoin concret.
4. **Donner une frontière de vue à la zone d’aperçu** (constat 4), via `aidd-dev:07-refactor` avec le skill Apple `swiftui-specialist`. Vérifier les transitions entre deux lectures et les états statique, chargement et indisponibilité. Aucun gain de latence n’est annoncé sans mesure.

Ces actions sont des recommandations. L’audit n’implémente aucune correction.

## Coverage

- **Examiné** — Pilier `architecture` : conformité au guide, direction des dépendances et répartition des responsabilités, complété par les frontières de sous-vues et d’observation décrites par Apple. Lecture de l’état d’historique, de la file d’aperçus, de l’assemblage de l’app, des modèles Domain/UseCases, du stockage SwiftData et des archives ; lecture de la structure des vues, des adaptateurs et des tests nécessaires aux constats.
- **Méthode** — Premier passage statique, puis relecture indépendante des références Apple et vérifications Xcode indiquées ci-dessus. Les constats de dette décrivent des dépendances observées et leurs conséquences sur la modification ou la substitution des composants ; ils ne démontrent pas un dysfonctionnement utilisateur.
- **Skipped** — Aucun contrôle architectural prévu n’a été bloqué. L’indépendance entre les quatre fonctionnalités reste partiellement évaluable : seul `ClipboardHistory` est actuellement implémenté dans `Features`.
- **Hors périmètre** — Les six autres piliers ne font pas l’objet d’un audit complet : qualité interne du code, sécurité, dépendances tierces, performances, couverture de tests et qualité UI. La lecture de quelques tests sert uniquement à vérifier les frontières de substitution. Aucun test, benchmark ou rendu Xcode n’a été lancé ; la compilation ne prouve ni la compatibilité d’exécution sur macOS 26 ni la latence sous charge.
- **Modifications** — Ce rapport est le seul ajout visible dans Git. Les réponses MCP et le journal sont des artefacts locaux ignorés dans `build/validation/`. Aucun code, réglage, donnée d’historique ou stash n’a été modifié. Aucun commit, push ou PR.
