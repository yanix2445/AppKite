# Coding Assertions

## Before commit

| Ordre | Outil MCP Xcode | Vérification |
| --- | --- | --- |
| 1 | `BuildProject` | Compiler le schéma `AppKite` à l’assert. |
| 2 | `RunAllTests` ou `RunSomeTests` | Exécuter les suites prévues par le plan et vérifier leurs résultats. |
| 3 | `RenderPreview` | Capturer les Previews pertinentes quand la feature comporte des vues. |

## Before push

- Après un assert réussi, faire la revue en lecture seule et obtenir le go explicite. Le commit et la PR suivent les règles de [VCS](vcs.md).

## Behavior

- Traiter chaque feature séparément. Faire valider chaque étape du flux `brainstorm → spec → plan → implement → assert → review → commit → pull request`. Vérifier la présence du skill avant chaque invocation.
- Consulter la documentation Apple via le MCP Xcode pendant le plan et l’implémentation avant d’utiliser une API. Toute dépendance tierce exige un accord préalable.
- Développer en clean-room. Utiliser les utilitaires de référence pour comparer les comportements et produire le code, les assets et les noms propres à AppKite.
- En cas d’échec à l’assert ou à la revue, retourner à l’implémentation, puis rejouer l’assert et la revue.
