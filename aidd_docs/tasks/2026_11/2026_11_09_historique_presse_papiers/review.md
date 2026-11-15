# Revue de l’historique du presse-papiers

## Round 1

- Périmètre `main...385c6f5`, avec les modifications locales et les fichiers non suivis de `feat/historique-presse-papiers`.
- Axes code, critères d’acceptation et pertinence.
- Verdict **blocked**. Deux chemins du nettoyage peuvent effacer une archive alors qu’aucune nouvelle carte n’a besoin de la place libérée.

### Critères

| Phase | Critère | État et preuve |
| --- | --- | --- |
| 1 | Une icône, actions du menu et relance | Satisfait. `AppKiteUITests.swift:12` et [49 tests réussis au dernier assert](assert.md#round-4). |
| 1 | Première copie, persistance, doublon texte et refus de lecture | Première copie, persistance, doublon texte et refus simulé couverts. Le refus du système reste à vérifier [sur un parcours réel](phase-1-validation.md). |
| 1 | Menu, raccourci, écran du pointeur, présélection et conflit | Les deux déclencheurs sont couverts par `AppKiteUITests.swift:44` et `:72`. Le contrôleur choisit l’écran du pointeur (`ClipboardPanelController.swift:126`) et conserve l’ancien raccourci si l’enregistrement échoue (`ClipboardHistoryState.swift:208`). La [mesure sur deux écrans](phase-4.md#état-de-la-validation) précède la dernière géométrie du bandeau. |
| 1 | Collage dans l’app cible, prochain ⌘V et repli | Collage réel, second ⌘V et fermeture de la cible exercés lors de la [phase 1](phase-1-validation.md). La suite actuelle vérifie notamment la conservation d’une copie intervenue entre-temps (`ClipboardRoundTripTests.swift:74`). |
| 2 | Épingles, collections, vidage et suppression protégée | Satisfait sur les chemins ordinaires. `ClipboardOrganizationTests.swift:34`, `:81` et `ClipboardHistoryUITests.swift:5`. |
| 2 | Pause persistée, reprise manuelle et échéance | Les deux reprises sont couvertes par `ClipboardHistoryPolicyTests.swift:8` et `:27`. L’archivage d’une autre copie peut retarder la collecte et faire sauter des changements intermédiaires. |
| 2 | Exclusions, confidentialité et origine inconnue | Satisfait pour les origines déclarées, les origines inconnues et le réglage des copies confidentielles. `ClipboardHistoryPolicyTests.swift:54`, `:98` et `ClipboardFormatTests.swift:243`. |
| 3 | Neuf familles et repli des tableurs | Les neuf familles ont été exercées sur un presse-papiers privé, avec formules, format et repli validés dans Numbers. Le repli est incomplet pour une copie uniquement disponible en CSV. [Validation des formats](phase-3.md#état-de-la-validation). |
| 3 | Archives Finder autonomes, sélection atomique et persistance | Satisfait sur les cas vérifiés. La copie complète précède la publication de la carte et aucune limite par copie n’est configurée. `ClipboardArchivedHistoryTests.swift:8`, `ClipboardArchiveTests.swift:60` et [essai APFS](phase-3.md#état-de-la-validation). |
| 3 | Nettoyage limité, ordonné et sûr en cas de capacité insuffisante | Partiel. Le [volume APFS isolé](assert.md#round-3) valide l’éviction ordinaire, les protections et un refus d’archivage prévisible. La recopie d’un fichier et les échecs après éviction restent des défauts. |
| 4 | Index texte, noms des dossiers, OCR et mutations | Satisfait sur les cas couverts. `ClipboardTextExtractorTests.swift:15`, `:50`, `:69`, `:107` et `ClipboardSearchTests.swift:42`. |
| 4 | Recherche et filtres combinés, épingles et validation clavier | Le même filtre s’applique à l’ensemble de l’index avant pagination. La validation sélectionne uniquement une carte visible. `ClipboardSearchIndex.swift:30`, `ClipboardSearchTests.swift:7` et `ClipboardHistoryState.swift:109`. |
| 4 | Latence et preuves sur les deux générations de macOS | Partiel. Sur 10 000 cartes, le p95 mesuré jusqu’au rendu demandé est de 45,45 ms au repos et 56,88 ms pendant l’archivage. L’affichage final à l’écran et macOS 26 restent sans mesure. Aucun parcours d’export long dans ce périmètre. [Mesure et méthode](phase-4.md#état-de-la-validation). |

### Hypothèses vérifiées

- L’origine déclarée et l’origine probable suivent des chemins distincts. Les filtres et exclusions utilisent l’origine déclarée. L’icône peut utiliser l’origine probable avec un point d’interrogation (`PasteboardClient.swift:133`, `ClipboardSearchIndex.swift:33`, `ClipboardHistoryView.swift:774`). Le marqueur distant conserve son propre affichage.
- Le bandeau occupe le bas de l’écran complet et sa fenêtre passe au-dessus du Dock. L’animation respecte la préférence de réduction des mouvements (`ClipboardPanelController.swift:29`, `:116`, `:154`).
- Le `.gitignore` local est présent parmi les fichiers non suivis et fait partie du périmètre de livraison défini dans le [plan](plan.md#impact).

### Défauts

- **P1 · Critique. Une recopie identique peut effacer des cartes ordinaires.** `ClipboardArchive.swift:202` écarte les fichiers du calcul d’empreinte préalable. Le stockage cherche le doublon après avoir écrit l’archive temporaire (`SwiftDataClipboardHistoryStore.swift:232`). Si cette écriture échoue par manque de place, `:149` peut évincer une autre carte avant que la seconde tentative reconnaisse le doublon. Cas concret avec un fichier inchangé sur un volume externe et un espace libre inférieur à sa taille. Calculer une empreinte stable de la sélection avant toute éviction, la comparer à l’historique, puis actualiser la carte existante sans créer de nouvelle archive.
- **P1 · Critique. Une tentative de récupération d’espace peut supprimer des cartes sans réussir à enregistrer la copie.** `SwiftDataClipboardHistoryStore.swift:201` valide chaque suppression en base et retire l’archive (`:355`, `:364`). La préparation de la nouvelle archive n’est relancée qu’après (`:150`). Un fichier retiré entre l’estimation et ce second essai, par exemple lors de l’éjection du volume source, entraîne un échec après des suppressions déjà définitives. Sécuriser la source et la publication de la nouvelle copie avant toute éviction irréversible. Quand cette garantie ne peut pas être obtenue, préserver les archives existantes et signaler l’échec. Couvrir un échec déclenché entre le calcul et la publication.
- **P2 · Majeur. Archiver un gros fichier peut faire manquer les copies suivantes.** La boucle attend la fin de `collect` avant de reprendre le sondage (`ClipboardHistoryState.swift:276`). `collect` attend lui-même l’écriture complète (`:299`). Pendant cette attente, deux copies successives remplacent la même valeur globale et seule la dernière peut être lue (`PasteboardClient.swift:104`, `:119`). Maintenir le sondage pendant l’archivage et conserver l’ordre des écritures. Vérifier avec une écriture suspendue et deux copies espacées de plus d’un intervalle de sondage.
- **P2 · Majeur. Un tableur copié uniquement en CSV n’a pas de repli standard en cellules.** Le CSV est reconnu comme représentation de tableur (`ClipboardFormatCodec.swift:15`, `:131`). La synthèse du repli ne lit que les variantes TSV ou le texte accompagnant une représentation native (`:58`). Comme le collage écrit seulement les représentations disponibles (`PasteboardClient.swift:220`), une copie CSV seule reste inutilisable comme plage dans une destination qui ne lit pas ce format. Conserver le CSV original et produire un repli tabulaire quand ses valeurs sont décodables. Couvrir les champs entre guillemets et les cellules vides.

### Limites

- Revue statique appuyée sur les validations déjà consignées. Les scénarios relevés restent à reproduire dans leurs tests de régression.
- macOS 26 est retenu par hypothèse à la demande de Yanis. Le refus d’accès système et le transfert Handoff entre deux appareils ont des tests simulés. Leurs parcours réels restent ouverts.

## Round 2

- Périmètre `main...385c6f5`, avec les corrections locales de `feat/historique-presse-papiers`.
- Axes code, critères d’acceptation et pertinence.
- Verdict **changes-requested**. La préservation des cartes est vérifiée. L’éviction automatique reste ouverte au regard du contrat de la phase 3.

### Critères

- [x] La recopie d’une sélection identique retrouve la carte avant de créer une archive temporaire. L’empreinte inclut les octets et les métadonnées pris en compte par l’empreinte de l’archive. `ClipboardArchive.swift:192`, `SwiftDataClipboardHistoryStore.swift:159` et test d’intégration `ClipboardArchivedHistoryTests.swift:7`.
- [x] Un échec de capacité laisse en place les cartes et les fichiers déjà archivés. Le chemin d’erreur n’appelle plus de suppression d’entrées. L’essai sur volume APFS vérifie les données après réouverture. `SwiftDataClipboardHistoryStore.swift:143` et [validation APFS](assert.md#round-5).
- [ ] Une pression disque récupérable entraîne une éviction automatique dans l’ordre de dernière utilisation. En cas de manque de place à l’écriture, le stockage conserve les cartes et signale que la copie n’a pas été archivée. La même opération réussit après libération d’espace. [Phase 3](phase-3.md#test-acceptance-criteria).
- [x] Le sondage continue pendant l’archivage. Les écritures consomment les copies dans l’ordre de leur capture. `ClipboardHistoryState.swift:277`, `:335` et `ClipboardHistoryPolicyTests.swift:54`.
- [x] Un CSV seul fournit un repli tabulaire au collage, y compris pour les cartes archivées avant la correction. Le repli conserve la représentation originale. `PasteboardClient.swift:220`, `ClipboardFormatCodec.swift:72` et `ClipboardFormatTests.swift:133`.

### Limites

- Les 55 tests sont réussis sur macOS 27.2.1. La fidélité des champs CSV multilignes dans chaque tableur de destination reste à vérifier. Les aperçus du dernier état sont en attente d’accès MCP. [Dernière validation](assert.md#round-5).
- L’écriture d’une nouvelle archive et la libération des blocs d’une archive précédente ne sont pas une opération atomique du stockage actuel. L’éviction reste à concevoir pour les cas où les anciennes données ne peuvent pas être conservées jusqu’à la validation de l’écriture.

## Round 3

- Périmètre `main...385c6f5`, avec la réserve et l’éviction APFS sur `feat/historique-presse-papiers`.
- Axes code, critères d’acceptation et pertinence.
- Verdict **approve** pour le correctif de nettoyage et sa reprise après interruption. [Vérification Xcode et APFS](assert.md#round-6).

### Critères

- [x] Un doublon se résout avant l’écriture et sans éviction. `SwiftDataClipboardHistoryStore.swift:174` et l’essai avec un original de 9 Mio venant d’un autre volume.
- [x] Les évictions couvrent le déficit dans l’ordre de dernière utilisation. Après publication, `SwiftDataClipboardHistoryStore.swift:232` ignore les cartes protégées, les archives utilisées par l’OCR courant et les archives dont aucun bloc utile n’est récupérable. L’essai a évincé une seule carte et vérifié les octets des cartes restantes.
- [x] Un échec tardif préserve l’historique. La sauvegarde unique à `SwiftDataClipboardHistoryStore.swift:218` précède l’effacement des anciens fichiers. Une erreur avant la sauvegarde retire la nouvelle archive et garde les anciennes.
- [x] La relance nettoie les dossiers orphelins selon les cartes validées. `ClipboardArchive.swift:332` et les deux interruptions déclenchées autour de la sauvegarde.
- [x] La réserve est préallouée, publiée d’un bloc et mesurée après sa libération. `ClipboardArchive.swift:280` et `:312`. L’essai contrôle ses blocs physiques et sa reconstitution.

### Limites

- La réserve occupe jusqu’à 16 Mio et peut diminuer sous pression. Une copie qui ne peut pas être complètement écrite avec la place disponible et la réserve déclenche le repli qui préserve toutes les cartes.
- Les interruptions vérifiées concernent le processus AppKite. Les essais ont été menés sous macOS 27.2.1, avec les limites de la validation système précédemment consignées.

## Round 4

- Périmètre `main...385c6f5` avec la totalité des changements locaux de `feat/historique-presse-papiers`, y compris les fichiers non suivis et le `.gitignore` demandé.
- Axes code, critères d’acceptation et pertinence.
- Verdict **blocked**. Le nettoyage au démarrage peut rendre l’historique inaccessible ou retirer des fichiers appartenant à une copie en cours de sauvegarde par une autre instance.

### Critères

| Phase | Critère | Résultat et preuve |
| --- | --- | --- |
| 1 | Icône unique, menu, quitter et relancer | Satisfait dans `AppKiteUITests.swift:12`. [Assert de clôture](assert.md#round-9). |
| 1 | Première copie, doublon, persistance et refus | Satisfait dans le parcours à un seul écrivain. Ouverture et archivage fragiles si le nettoyage échoue ou si deux instances partagent le stockage. Refus réel reporté avec accord, et reprise exercée par simulation. [Validation de la phase 1](phase-1-validation.md#reprise-sur-macos-2721). |
| 1 | Appels par menu et raccourci, position et présélection | Satisfait par les tests du menu et du raccourci et les sondes de position et de conflit. `ClipboardHistoryState.swift:83`, `AppKiteUITests.swift:44` et `:72`. |
| 1 | Collage dans la cible, second collage et repli | Le parcours Texte, le second collage et la cible fermée ont été exercés. La livraison d’un événement à un processus n’établit pas l’insertion lorsqu’une app l’ignore. [Sonde inter-apps](phase-1-validation.md). |
| 2 | Épingles, collections, vidage et suppression | Organisation et protection couvertes par `ClipboardOrganizationTests.swift:34` et `:81`. La suppression de la carte est validée avant l’effacement de l’archive, qui peut échouer. |
| 2 | Pause persistée et reprises manuelle et programmée | Satisfait dans `ClipboardHistoryPolicyTests.swift:8` et `:27`. |
| 2 | Exclusions et confidentialité indépendantes | Satisfait selon la provenance déclarée. L’origine inconnue peut être archivée. `PasteboardClient.swift:128` et `ClipboardHistoryPolicyTests.swift:110`. |
| 3 | Neuf familles de copies et repli tabulaire | Satisfait dans les parcours couverts par les tests de formats et le collage Numbers. [Phase 3](phase-3.md#état-de-la-validation). |
| 3 | Fichiers et dossiers persistants, sélection indivisible et échec signalé | La restitution après suppression des originaux et le rejet de la sélection complète sont couverts. Le signal d’échec peut être effacé avant l’ouverture du bandeau. `ClipboardArchiveTests.swift:8` et `:60`, `ClipboardHistoryState.swift:299`. |
| 3 | Nettoyage prévisible, ordonné et limité | Le scénario APFS exercé confirme le choix des cartes éligibles et l’ordre de dernière utilisation. Le traitement d’une archive orpheline impossible à retirer reste défaillant. [Essai APFS](assert.md#round-6). |
| 4 | Index texte, dossiers, OCR et mutations | Satisfait par `ClipboardTextExtractorTests.swift:15`, `:50`, `:69`, `:107` et `ClipboardSearchTests.swift:42`. |
| 4 | Filtres combinés, épingles et validation d’une carte visible | Satisfait pour les résultats et la sélection. Des vignettes visibles restent absentes dans un cas de pagination. `ClipboardSearchTests.swift:7`, `ClipboardHistoryState.swift:116` et `:441`. |
| 4 | Latence au p95 et versions de macOS visées | 90,50 ms au repos et 106,16 ms sous archivage, sur 10 000 cartes sous macOS 27.2.1. L’hypothèse de compatibilité macOS 26 a été acceptée. [Mesure à l’écran](assert.md#round-8). |

### Hypothèses vérifiées

- `App` assemble le menu et les réglages autour du même état. Le projet inclut les fichiers de la feature avec sa cible existante. `AppKiteApp.swift:13`.
- Le stockage suppose un écrivain unique. L’acteur sérialise les opérations d’une instance. Le dossier partagé par les instances et la réconciliation au lancement ne sont pas protégés par un verrou commun. `SwiftDataClipboardHistoryStore.swift:24` et `:443`.
- Les exclusions utilisent l’origine déclarée. L’origine probable reste un indicateur visuel. `PasteboardClient.swift:133`, `:183` et `ClipboardHistoryView.swift:774`.
- Le `.gitignore` local couvre les réglages utilisateur Xcode, les résultats de tests, les artefacts de compilation et de couverture. Les retouches de contexte dans `AGENTS.md` et `CLAUDE.md` sont distinctes du code de la feature et sont à laisser hors du commit de cette feature.

### Défauts

- **P1 · Critique. Une archive impossible à effacer peut empêcher l’ouverture de tout l’historique.** La suppression enregistre d’abord le retrait de la carte, puis retire le fichier (`SwiftDataClipboardHistoryStore.swift:342`). Si un fichier importé avec une ACL de refus de suppression reste orphelin, le repli ne traite que les verrous et les modes POSIX (`ClipboardArchive.swift:569`, `:582`). La réconciliation propage ensuite le même échec au démarrage (`ClipboardArchive.swift:342`, `SwiftDataClipboardHistoryStore.swift:35`). Préserver l’accès aux archives valides pendant un nettoyage partiel et traiter les ACL de suppression sur les seules copies internes. Couvrir la suppression puis la réouverture avec un fichier dont la lecture est autorisée et la suppression refusée. [ACL lors d’une copie](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemDetails/FileSystemDetails.html) · [Contrôle de suppression dans XNU](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_subr.c#L9466-L9540).
- **P1 · Critique. Deux instances peuvent laisser une carte sans son archive.** Les deux ouvertures partagent la même base et les mêmes répertoires (`SwiftDataClipboardHistoryStore.swift:24`, `:443`). La seconde prend la liste des cartes puis efface les archives absentes de sa liste (`SwiftDataClipboardHistoryStore.swift:371`, `ClipboardArchive.swift:332`). Si la première a publié un fichier et poursuit sa sauvegarde avant ou pendant ce nettoyage, la carte peut être validée alors que son archive a été retirée (`SwiftDataClipboardHistoryStore.swift:207`, `:218`). Imposer l’accès exclusif au stockage avant la réconciliation et pendant les mutations, en signalant clairement une seconde ouverture.
- **P2 · Majeur. Un rejet d’archivage peut disparaître avant que l’utilisateur le voie.** Bandeau fermé, effectuer une copie refusée faute de place, puis une copie valide. Le succès efface `historyMessage` (`ClipboardHistoryState.swift:299`) avant que le bandeau puisse afficher le rejet (`ClipboardHistoryView.swift:70`). Garder un signal de l’échec jusqu’à consultation ou le rendre visible dès le rejet.
- **P2 · Majeur. Des images dans les pages suivantes peuvent rester sans vignette.** Le lot est limité aux 48 premières cartes sans vignette en cache (`ClipboardHistoryState.swift:441`). Une page de tableurs sans vignette revient dans chaque demande puisque le stockage n’en renvoie aucune (`SwiftDataClipboardHistoryStore.swift:60`). Une image chargée ensuite peut être exclue du lot à chaque recherche. Sélectionner les cartes ayant une vignette à partir des métadonnées ou retenir les lectures sans vignette, puis vérifier le chargement après pagination.
- **P2 · Majeur. Trois tests d’interface ouvrent l’historique du compte qui exécute les tests.** `AppKiteUITests.swift:15`, `:46` et `:74` lancent l’application avec son emplacement par défaut. La collecte démarre automatiquement (`ClipboardHistoryState.swift:74`) et peut lire ou modifier l’historique du Mac pendant les tests. Appliquer un historique et des préférences temporaires à chacun de ces tests, comme dans `ClipboardHistoryUITests.swift:8`.

### Limites

- Revue statique qui s’appuie sur les 55 tests et les aperçus du [Round 9](assert.md#round-9). Les scénarios remontés sont établis en suivant le code. Leur correction devra rejouer les cas de régression correspondants.
- Le refus système réel est reporté avec accord. macOS 26 reste retenu par hypothèse. La latence a été mesurée à partir de la mise à jour du champ jusqu’à l’image présentée par le serveur de fenêtres.

## Round 5

- Périmètre de contre-revue limité aux cinq défauts du Round 4 et au signalement des sélections Finder invalides.
- Axes code, critères d’acceptation et pertinence.
- Verdict **approve**. Les cinq défauts sont corrigés et les scénarios correspondants passent. [Assert Round 10](assert.md#round-10).

| Défaut | Correction vérifiée |
| --- | --- |
| Archive protégée bloquant la relance | Le retrait des ACL intervient lors de la suppression des copies internes. La réconciliation poursuit son parcours après un échec local. `ClipboardArchive.swift:335` et `:593`. |
| Ouvertures concurrentes | Le verrou du dossier est acquis avant SwiftData et détenu pendant la durée de vie du stockage. Une seconde instance affiche un message dédié. `SwiftDataClipboardHistoryStore.swift:27` et `ClipboardHistoryState.swift:330`. |
| Signalement d’une copie refusée | Le message d’archivage persiste jusqu’à sa fermeture. Une sélection Finder invalide est signalée une fois par changement du presse-papiers. `ClipboardHistoryPolicyTests.swift:110` et `:218`. |
| Vignettes après pagination | Le chargement parcourt les lots et mémorise les réponses sans vignette pour les cartes affichées. Seule la recherche en cours publie les vignettes. `ClipboardHistoryState.swift:446` et `ClipboardHistoryPolicyTests.swift:131`. |
| Historique réel utilisé par XCTest | La fixture partage un dossier temporaire entre les lancements d’un seul test et le supprime après terminaison de l’app. `IsolatedAppKite.swift:8`. |

Le `.gitignore` local est inclus dans le périmètre de la feature. Les vérifications système et leurs limites figurent dans l’assert.
