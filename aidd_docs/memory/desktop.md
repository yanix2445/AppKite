# Desktop

## Framework

- Utilitaire de barre de menus macOS natif pour Apple Silicon. Les versions cibles et le schéma Xcode sont dans le [guide technique](../INSTALL.md#stack-summary).

## Native access

- AppKite est conçu hors App Sandbox pour les opérations inter-apps, avec Hardened Runtime et les permissions macOS demandées à l’usage. Le réglage du modèle se lit dans le [projet Xcode](../../AppKite.xcodeproj/project.xcproj).
- Vérifier `#available` à la frontière de l’API, avec sa version d’introduction précise. Garder le repli près de l’appel macOS. La spec fixe le résultat sur chaque version et fait valider les écarts de comportement.
- Distinguer la présence d’une fenêtre de la disponibilité de sa miniature. Vérifier les limites du filtre par Space et du flux des fenêtres minimisées avec les API publiques. [Apple · Capture de fenêtres](https://developer.apple.com/videos/play/wwdc2022/10155/)
- La disponibilité du presse-papiers et l’origine d’une copie sont deux informations distinctes. La règle d’exclusion doit définir le cas où l’origine est incertaine. [Apple · NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard/)

## Build and release

- Utiliser les outils et skills fournis par Xcode. Le MCP officiel sert de point d’accès à Xcode dans Codex et Claude Code.
- Distribuer d’abord par builds locaux, puis par téléchargement direct depuis GitHub Releases.
- Pour la version publique, signer `AppKite.app` avec `Developer ID Application` et notariser la distribution via l’adhésion Apple Developer Program existante. Joindre le ticket de notarisation à la distribution. [Apple · Notarisation macOS](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- Tester le premier lancement depuis le ZIP et le DMG avec Gatekeeper activé, puis vérifier que la mise à jour conserve les autorisations de l’app. [Apple · Validation de la distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
