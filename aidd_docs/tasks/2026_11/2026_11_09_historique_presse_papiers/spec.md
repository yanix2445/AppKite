# Historique du presse-papiers · V1

## Target

Permettre de retrouver une copie dans l’historique local d’AppKite et de la recoller dans l’app qui était active à l’ouverture du bandeau.

## Hard constraints

- L’historique fonctionne hors ligne, sans compte, sur Apple Silicon sous macOS 26.0 ou ultérieur. Les critères d’acceptation s’appliquent sous macOS 26 et 27.
- L’historique et les contenus archivés restent sur le Mac et persistent après une relance d’AppKite. La conservation est sans expiration automatique ni plafond de taille par copie. L’espace disque disponible et les règles de nettoyage déterminent si une copie peut être archivée.
- Le collage préserve les données fournies lors de la copie que l’app de destination peut restituer. Les neuf familles suivantes entrent dans le périmètre de la V1.

| Famille | Résultat attendu au collage |
| --- | --- |
| Texte simple | Le texte, ses caractères, ses espaces et ses retours à la ligne sont restitués. |
| Texte enrichi | Le texte conserve la mise en forme fournie, dont les listes et les liens intégrés. |
| Liens | L’URL est restituée. |
| Images | L’image elle-même est recollable, y compris une capture d’écran copiée. |
| Fichiers et dossiers du Finder | Un fichier, un dossier ou une sélection est recollable en bloc à partir de la copie archivée, même après suppression de l’original. |
| Cellules de tableur | La plage conserve ses lignes et colonnes, ses formules et sa mise en forme si le format de la copie et le tableur de destination le permettent. Les valeurs sont restituées dans les mêmes lignes et colonnes comme repli quand elles sont disponibles. |
| PDF et dessins vectoriels | Le PDF ou le dessin copié sous forme de contenu PDF est recollable dans une app qui accepte ce format. |
| Couleurs | La nuance copiée depuis un sélecteur est recollable comme couleur dans une app qui accepte ce format. |
| Contenus mixtes | Le texte et les images intégrées ou pièces jointes fournis ensemble sont recollables ensemble dans une app qui accepte ce contenu. |

## Non-goals

- La synchronisation de l’historique entre appareils relève d’un chantier distinct.
- La restitution d’objets natifs tels que les diapositives et les calques de design relève d’un périmètre distinct.
- La recherche dans le contenu des fichiers imbriqués dans un dossier archivé relève d’un périmètre distinct. Un dossier est retrouvé par son nom.

## Done-when

- Le menu AppKite et le raccourci global configurable `⇧⌥V` par défaut ouvrent le même bandeau de cartes avec de grands aperçus. Le bandeau s’ouvre en bas de l’écran où se trouve le pointeur au moment de l’ouverture. La carte la plus récente est présélectionnée. `Entrée` valide la carte sélectionnée.
- Valider une carte colle son contenu dans l’app qui était active à l’ouverture du bandeau. Le contenu choisi reste dans le presse-papiers macOS pour le prochain `⌘V`. Si le collage direct est indisponible, AppKite place le contenu choisi dans le presse-papiers et affiche « Copié. Colle avec ⌘V. » après réussite de la copie.
- Après le lancement, dès que macOS autorise l’accès, la première nouvelle copie admissible apparaît dans l’historique. Le contenu qui se trouvait déjà dans le presse-papiers au lancement est ignoré. Depuis le menu AppKite, une pause suspend l’enregistrement et laisse les cartes consultables. L’utilisateur peut reprendre manuellement ou choisir une durée au terme de laquelle l’enregistrement reprend. Une pause active se poursuit après relance jusqu’à la reprise manuelle ou jusqu’à son échéance. Les copies faites pendant la pause sont écartées.
- Quand macOS refuse l’accès au presse-papiers, l’enregistrement des nouvelles copies est suspendu et les cartes archivées restent consultables. Le bandeau affiche « Autorise l’accès au presse-papiers pour reprendre l’enregistrement » et propose le bouton **Ouvrir les Réglages Système**.
- Une copie identique remonte la carte existante et actualise son origine à celle de la copie la plus récente. L’épingle et les collections de la carte sont conservées. Recoller une carte depuis le bandeau la remonte aussi dans l’historique.
- La recherche retrouve les cartes par le texte copié, les URL, les valeurs de cellules, les noms de fichiers et de dossiers, et le texte de toutes les images et de tous les PDF copiés directement. Les filtres par type et par app d’origine se combinent entre eux et fonctionnent avec ou sans recherche saisie. Une recherche active affiche uniquement les cartes correspondantes, y compris dans la section des épingles. Les premiers résultats s’affichent en moins de 200 ms au p95 sur un historique de 10 000 entrées mixtes. Cette cible s’applique aussi sous charge pendant un export long dès que ce parcours existe dans AppKite.
- Les cartes épinglées disposent d’une section visible en tête du bandeau. Une même carte peut figurer dans plusieurs collections et reste accessible depuis l’historique. Supprimer une collection retire le regroupement. Ses cartes restent dans l’historique et dans leurs autres collections. « Vider l’historique » conserve les cartes épinglées ou classées. La suppression définitive d’une carte protégée est possible directement depuis le bandeau après confirmation et efface aussi son contenu archivé.
- Lorsque tous les fichiers d’une sélection du Finder peuvent être archivés, une seule carte permet de les recoller ensemble. Si l’archivage de l’un des fichiers échoue, AppKite écarte la sélection entière et le signale. En cas de manque de place, le nettoyage efface les cartes ni épinglées ni classées en commençant par celles utilisées le moins récemment, à concurrence de l’espace nécessaire. La date d’utilisation correspond au plus récent événement entre une copie et un collage depuis le bandeau. AppKite vérifie d’abord que l’espace nécessaire est récupérable. S’il ne l’est pas, l’historique est préservé et AppKite signale que la copie n’a pas été archivée.
- Une exclusion par app écarte les nouvelles copies attribuées à cette app et conserve les cartes existantes. Une origine inconnue laisse la copie admissible. Une copie explicitement signalée comme confidentielle est écartée sur ce motif uniquement lorsque le réglage correspondant est actif. Ce réglage est activé par défaut et s’applique indépendamment des exclusions par app.

## Open Questions

None

## Context

- [Brainstorm approuvé](brainstorm.md)
- [Périmètre produit](../../../memory/project-brief.md#ordre-de-livraison)
- [Compatibilité et objectifs de vérification](../../../INSTALL.md#tests-et-critères-de-vérification)
