# Review: Socle et barre de menus

- Rounds: 2
- Started: 2026-11-09

## Round 1 · r-ee20

- Date: 2026-11-09
- By: yanis
- Diff: `main...0232c94e56bc74f5c4e10154fc1a6c0acd461fd5` et arborescence de travail, index et fichiers non suivis inclus
- Axes: code, functional, relevancy
- Verdict: changes-requested
- Score: 2/3 met, 0 unmet, 1 unverified at runtime, 0 out of the diff

### Criteria

- [x] Cibles Swift 6 sur Apple Silicon, bundle `LSUIElement = true`, minimum macOS 26.0 et signature conforme aux réglages approuvés. [Assert](assert.md)
- [x] Lancement manuel, accès par la seule barre de menus, menu natif à une seule action, fermeture du processus et retrait de l’icône sur macOS 27.2. [Assert](assert.md)
- Unverified at runtime: Le parcours complet passe sur macOS 27.2, y compris la relance et le mode hors ligne. Les deux tests et la Preview ont été exécutés via le MCP Xcode. Le parcours sous macOS 26 reste à vérifier avant diffusion publique, selon l’accord `go 27`. [Assert](assert.md)

### Findings

- Les deux passages du test d’interface réussissent avec un avertissement sur le thread principal. Dans le journal Xcode, il apparaît pendant le premier comptage des icônes et le résultat ne fournit aucune ligne source. Isoler ce comptage en implémentation et vérifier que le test conserve son contrôle d’unicité sans cet avertissement. 🟡 major, code-health. [AppKiteUITests.swift:25](../../../../AppKiteUITests/AppKiteUITests.swift#L25)
- La mémoire AIDD pointe encore vers l’ancien point d’entrée et le modèle Xcode supprimé. Mettre à jour le chemin d’`AppKiteApp.swift` et retirer le lien vers `Item.swift`. 🟢 minor, rot. [Codebase Map](../../../memory/codebase-map.md) · [Database](../../../memory/database.md)
- L’index contient l’ajout d’`Untitled.swift`. L’arborescence contient aussi un point d’arrêt Xcode local et `default.profraw`, un profil de couverture issu de la vérification. Écarter ces fichiers du commit du socle par une sélection explicite de son périmètre. 🟢 minor, fit.

## Round 2 · r-c1cc

- Date: 2026-11-09
- By: yanis
- Diff: `main...0232c94e56bc74f5c4e10154fc1a6c0acd461fd5` et arborescence de travail, index et fichiers non suivis inclus
- Axes: code, functional, relevancy
- Verdict: approve
- Score: 2/3 met, 0 unmet, 1 unverified at runtime, 0 out of the diff

### Criteria

- [x] Les trois cibles Swift 6 compilent pour Apple Silicon. Le bundle contient `LSUIElement = true`, cible macOS 26.0 et porte une signature avec Hardened Runtime. Les réglages du projet désactivent App Sandbox pour la cible AppKite. [Nouvel assert](assert.md#nouvel-assert-après-la-reprise-du-9-novembre-2026)
- [x] Sous macOS 27.2, le lancement manuel affiche une seule icône, le menu natif propose uniquement « Quitter AppKite » et la fermeture retire l’icône. Le diagnostic de confiance du framework `Security` apparaît dans le processus AppKite au lancement et à la relance. La vérification statique ne relève aucun appel direct à l’évaluation de confiance et le parcours aboutit à chaque passage. L’appel déclencheur reste à identifier. [Nouvel assert](assert.md#nouvel-assert-après-la-reprise-du-9-novembre-2026)
- Unverified at runtime: Les deux passages du MCP Xcode valident les deux tests et la Preview sous macOS 27.2. Les contrôles hors ligne couvrent aussi le lancement, la fermeture et la relance. L’exécution sous macOS 26 reste à vérifier avant diffusion publique selon le périmètre approuvé. [Nouvel assert](assert.md#nouvel-assert-après-la-reprise-du-9-novembre-2026)

### Findings

- L’index contient `Untitled.swift`. Le point d’arrêt Xcode local et le profil de couverture `default.profraw` sont présents dans l’arborescence de travail. Sélectionner explicitement les fichiers du socle au commit pour écarter ces éléments hors périmètre. 🟢 minor, fit. [Règles VCS](../../../memory/vcs.md#commit-strategy)
