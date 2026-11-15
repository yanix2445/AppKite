# Validation de la phase 1

Le feu vert « go 27 pour la phase 1 » fixe le périmètre de cette passe au Mac Apple Silicon hôte sous macOS 27.2 (26B123), avec un écran. Les essais sous macOS 26 et sur deux écrans sont reportés à la validation finale.

| Vérification | Résultat observé |
| --- | --- |
| Suite Xcode `AppKite` | Neuf tests réussis, dont l’ouverture du bandeau via `⇧⌥V` depuis le Finder et la reprise de collecte après un changement d’autorisation simulé. |
| Première nouvelle copie | Un historique de test isolé a conservé le nouveau texte et écarté le contenu présent au lancement. |
| Collage entre deux apps | La fenêtre cible a reçu le texte accentué sur deux lignes après `Entrée`, puis le même texte au `⌘V` suivant. |
| Fermeture de l’app cible | Après fermeture de la cible et validation de la carte, le texte exact était disponible dans le presse-papiers. |
| Origine d’une copie dans Safari et Mail | Une sélection dans une page Safari locale et une sélection dans le champ Objet d’un message Mail de test ont produit le texte attendu sans marqueur `org.nspasteboard.source`. Dans ces cas, l’origine est inconnue. Le filtre et l’exclusion par app dépendent d’une attribution disponible. |
| Refus et reprise | Le test sur un presse-papiers privé a contrôlé l’arrêt de la collecte sous refus simulé, le rejet du contenu copié pendant ce refus et la reprise à la première nouvelle copie. |

Le dialogue réel de lecture reste à vérifier. La copie de test d’AppKite a lu le presse-papiers sur ce Mac malgré le mode développeur décrit par Apple, et Réglages Système n’a pas présenté de contrôle d’accès au presse-papiers pour cette copie. L’essai Handoff reste à faire avec un second appareil compatible. [Apple · Confidentialité du presse-papiers](https://developer.apple.com/documentation/updates/appkit?changes=latest_ma_3)

La [phase 1](phase-1.md) reste `in-progress` pour les vérifications de refus réel et de Handoff.

La revue Apple a corrigé la résolution de la touche `V` selon la disposition du clavier, la sélection de l’app cible à l’ouverture et la protection d’une copie arrivée avant l’écriture de la carte. Le bandeau distingue aussi un refus explicite d’un échec de lecture dont la cause est inconnue. La suite complète passe sur macOS 27.2 avec **11 tests réussis**. Elle couvre la conservation d’une copie plus récente, une donnée promise indisponible et le retour au Finder après fermeture du bandeau. Le journal des tests d’interface contient encore le diagnostic Apple `Security` sur le thread principal déjà observé pendant la validation du socle.

## Reprise sur macOS 27.2.1

- Un second enregistrement exclusif via HIToolbox a provoqué un conflit réel. AppKite a signalé le conflit. Le raccourci précédent est resté enregistré et sa valeur a été conservée dans les préférences isolées.
- Avec un écran actif, le panneau natif a occupé le bas de l’écran du pointeur en utilisant `screen.frame`. Son niveau a été comparé à celui du Dock. Le résultat était supérieur d’un niveau.
- Avec `.alwaysDeny` injecté, le bandeau affichait « Autorise l’accès au presse-papiers pour reprendre l’enregistrement » et le bouton pour les Réglages Système. La fiche déjà archivée restait dans l’état présenté au bandeau.
- Deux applications de test isolées, l’une en `LSUIElement` et l’autre avec un cycle de premier plan standard, ont lu l’option `EnablePasteboardPrivacyDeveloperPreview` comme active. Les deux ont obtenu `.alwaysAllow` avant et après leur lecture programmatique de `NSPasteboard.general`. Les préférences de test ont été retirées. Le refus système reste sans reproduction sur cet hôte. [AppKit · option développeur](https://developer.apple.com/documentation/updates/appkit).
- Dans Réglages Système, la section Confidentialité et sécurité ne présentait aucun contrôle spécifique au presse-papiers. La recherche « presse-papiers » ne renvoyait aucun résultat.
- Les notes de version de macOS 27.2 confirment le retrait de `EnablePasteboardPrivacyDeveloperPreview` (186955507). La méthode de prévisualisation décrite dans les notes AppKit d’avril 2025 ne peut donc plus provoquer l’alerte sur l’hôte 27.2.1. La propriété publique `NSPasteboard.accessBehavior` continue à lire l’état décidé par le système. Pour vérifier un vrai refus, il faut un environnement qui présente l’alerte ou un réglage par application. [Notes de version de macOS 27.2](https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes) · [État d’accès AppKit](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-9k4t4).
- Handoff a été vérifié avec un iPhone physique. Yanis a copié depuis Notes le texte synthétique « Appkite handoff 5841 » et a confirmé son apparition dans TextEdit. Lors d’une nouvelle copie sur l’iPhone, le `PasteboardClient` d’AppKite a reçu le texte marqué comme distant sur le Mac, sans origine locale attribuée. Après enregistrement et réouverture de la base isolée, `PasteClipboardEntry` a restitué le même texte au presse-papiers de test. [Presse-papiers universel Apple](https://support.apple.com/fr-fr/102430).
- Le 15 novembre 2026, Yanis a validé le report de l’essai du refus réel. La preuve de la réaction d’AppKite repose sur les tests simulés tant qu’un environnement macOS ne permet pas de déclencher ce refus.
