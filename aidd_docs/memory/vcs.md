# VCS

## Setup

- Branche par défaut `main`. La branche locale suit `origin/main`.
- Dépôt GitHub public `yanix2445/AppKite`. Le remote `origin` pointe vers `https://github.com/yanix2445/AppKite.git`. Utiliser Git et la CLI `gh` et vérifier le remote avant toute opération distante.
- Suivre les tickets dans [GitHub Issues](https://github.com/yanix2445/AppKite/issues). Les consulter avec `gh issue view <numero>`. Utiliser `aidd-vcs:04-issue-create` et faire valider le ticket avant sa création.
- GitHub Releases est le canal de publication retenu.

## Branches

- Créer une branche par chantier depuis `main` et ouvrir la PR vers `main`.
- Nommer la branche `type/description-courte` ou `type/numero-description-courte` quand un ticket existe. Exemple `feat/42-socle-barre-menus`.
- Utiliser les préfixes AIDD `feat/`, `fix/`, `docs/`, `refactor/`, `chore/`, `test/` et `hotfix/`.

## Commits

- Produire des commits atomiques via `aidd-vcs:01-commit` après l’assert et la revue de la feature.
- Suivre [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) avec le modèle AIDD. Format `type(scope): description`, avec un scope facultatif comme `menu-bar` ou `clipboard`.
- Écrire la description en anglais, à l’impératif, en minuscules et sans point final, sur 72 caractères au maximum. Le corps facultatif explique la raison du changement. Référencer le ticket quand il existe.
- Utiliser `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`, `style`, `ci` ou `revert` selon le changement.
- Signaler une rupture avec le footer `BREAKING CHANGE: <description>`. Le titre peut aussi la signaler avec `!`.
- Le hook local [`commit-msg`](../../.githooks/commit-msg) contrôle la forme du message. Il laisse Git créer les commits de fusion. Dans chaque clone, l’activer avec `git config --local core.hooksPath .githooks`.

## Commit Strategy

- Chaque commit, push ou ouverture de PR requiert un go explicite. Sélectionner les fichiers du périmètre approuvé lors de la préparation du commit.
- Au démarrage, effectuer les [vérifications Xcode en local](coding-assertions.md#before-commit) pendant l’assert AIDD. Le contrôle porte sur la compilation, les tests prévus par le plan et les Previews pertinentes. GitHub Actions n’est pas requis pour la fusion à ce stade.

## Pull Requests

- Faire valider le titre, le contenu et la branche cible avant d’ouvrir la PR en brouillon via `aidd-vcs:02-pull-request`.
- Pour le tri des PR, appliquer `enhancement` à `feat/`, `bug` à `fix/` et `hotfix/`, et `documentation` à `docs/`, si le label existe sur GitHub. Pour les tickets, choisir parmi les labels existants selon le contenu et les faire valider avant la création.
- AppKite est maintenu en solo. Après la revue AIDD, Yanis donne le feu vert avant la fusion. Le ruleset GitHub exige zéro approbation formelle, ce qui permet à Yanis de fusionner ses propres PR.
- Intégrer les PR dans `main` avec **Create a merge commit**. Les commits de la branche de travail conservent leurs SHA, et un commit marque la fusion de la PR.
- Le [ruleset GitHub Protection de main](https://github.com/yanix2445/AppKite/rules/26824710) impose une PR et le merge commit sur `main`. Il bloque les force-push et la suppression de la branche.

## Releases

- Commencer les builds internes à `0.1.0`. Réserver `1.0.0` à la première version publique stable.
- La cible AppKite du [projet Xcode](../../AppKite.xcodeproj/project.xcproj) porte la version (`MARKETING_VERSION`) et le numéro de build (`CURRENT_PROJECT_VERSION`).
- Partir du build `1`. Après la validation de chaque fonctionnalité complète, augmenter le numéro de `1`, puis générer le build à partir de l’état validé. Les compilations de travail utilisent le numéro en cours. Le compteur continue quand la version change.
- Avant de distribuer un nouveau binaire, vérifier que son numéro de build est supérieur à celui du dernier binaire distribué. [Règle Apple pour macOS](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- Après `1.0.0`, signaler avec `BREAKING CHANGE` toute mise à jour qui retire une compatibilité annoncée, par exemple la prise en charge d’une version de macOS ou la lecture des collections déjà enregistrées. Une migration qui permet de retrouver ces données préserve la compatibilité.
- Pour une publication, suivre les règles de `aidd-vcs:03-release-tag` pour la version, les notes et le tag. Le calcul par défaut examine les commits depuis le dernier tag. Une rupture donne une majeure, une `feat` donne une mineure et les autres cas donnent un patch. Le passage par une PR avant le tag adapte la séquence à la protection de `main`.
- Préparer le commit de version sur `chore/release-X.Y.Z`, à partir de `main`. Mettre à jour la version et le numéro de build Xcode, puis intégrer le commit à `main` par une PR.
- Générer le binaire à partir du commit de version intégré à `main`, puis le signer, le notariser et le vérifier selon la [procédure macOS](desktop.md#build-and-release). Faire valider le binaire, la version, les notes et les fichiers concernés avant de créer et pousser le tag annoté `vX.Y.Z` sur ce commit.
- Publier la GitHub Release associée au tag avec les notes de version et deux fichiers, un `.zip` et un `.dmg`. Les deux contiennent le même build validé d’`AppKite.app`.
