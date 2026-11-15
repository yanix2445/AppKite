---
status: approved
---

# Historique du presse-papiers · V1

AppKite permet de retrouver une ancienne copie sur le Mac et de la recoller dans l’app où l’utilisateur travaillait.

## Bandeau et collage

- Un bandeau de cartes avec de grands aperçus s’ouvre en bas de l’écran depuis le menu AppKite ou un raccourci global configurable. La carte la plus récente est présélectionnée. `Entrée` colle la carte sélectionnée dans l’app qui était active à l’ouverture du bandeau.
- Le contenu choisi reste dans le presse-papiers macOS après le collage. Si le collage direct est indisponible, AppKite copie l’élément et affiche « Copié. Colle avec ⌘V. »

## Contenus et recherche

- La V1 couvre le texte simple, le texte enrichi, les liens, les images, les fichiers et dossiers du Finder, les cellules de tableur, les PDF et dessins vectoriels, les couleurs et les contenus mixtes.
- Le collage d’une plage de cellules restitue les formules et la mise en forme quand le format fourni et l’app de destination le permettent. Les valeurs en lignes et colonnes servent de repli.
- La recherche couvre le texte copié, les URL, les valeurs des cellules, les noms de fichiers et de dossiers, et le texte des captures d’écran et des PDF copiés directement. Les dossiers sont retrouvés par leur nom.
- Les filtres par type de contenu et par app d’origine sont combinables, même sans texte de recherche. Une recherche affiche uniquement les cartes correspondantes, épingles comprises.

## Enregistrement et confidentialité

- La surveillance démarre au lancement dès que macOS l’autorise. L’historique commence à la première nouvelle copie. Le menu AppKite permet de suspendre l’enregistrement avec reprise manuelle ou automatique après une durée choisie. Les cartes restent consultables pendant la pause.
- Une copie identique remonte la carte existante en gardant son épingle et ses collections. Le filtre par app utilise l’origine de la copie la plus récente. Recoller une carte depuis le bandeau la remonte également.
- Une exclusion par app écarte les nouvelles copies attribuées à cette app. Les cartes déjà archivées restent disponibles et les copies d’origine inconnue restent admissibles. Un réglage indépendant, activé par défaut, écarte les copies explicitement signalées comme confidentielles.

## Épingles, collections et conservation

- Les cartes épinglées ont une section en tête du bandeau. Une carte peut figurer dans plusieurs collections et reste accessible dans l’historique. « Vider l’historique » garde les cartes épinglées ou classées. La suppression définitive d’une carte protégée est possible directement depuis le bandeau après confirmation et efface son contenu archivé.
- L’historique reste sur le Mac, sans expiration automatique ni plafond de taille par copie. AppKite conserve des copies locales des fichiers et dossiers du Finder, recollables après suppression des originaux. Une sélection du Finder est archivée et recollée en bloc. Si l’archivage d’un fichier échoue, AppKite écarte toute la sélection et le signale.
- En cas de manque de place, AppKite vérifie d’abord si le nettoyage peut libérer assez d’espace. Si oui, il supprime les cartes les plus anciennes parmi celles qui ne sont ni épinglées ni classées, à concurrence de l’espace nécessaire. Sinon, il conserve l’historique et signale que la copie n’a pas été archivée.
