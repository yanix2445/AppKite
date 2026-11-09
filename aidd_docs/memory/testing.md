# Testing

## Strategy

- Swift Testing couvre la logique et les intégrations dans `AppKiteTests`. XCTest et XCUIAutomation couvrent les parcours d’interface dans `AppKiteUITests`.
- Mesurer avec XCTest et Instruments le temps jusqu’à la liste du switcher et aux premiers résultats de recherche. Cible inférieure à 200 ms au p95 sur le jeu mixte de 10 000 entrées, y compris sous charge pendant un export long.
- Exercer les replis et les chemins récents sur les deux générations de macOS prises en charge. Vérifier les comportements avec autorisation accordée ou refusée lorsque la feature dépend d’une permission.

## Tools

- Utiliser les outils Apple et le skill Xcode `modernize-tests` pour les conventions de test. Les outils MCP et leur ordre sont dans [Coding Assertions](coding-assertions.md).

## Conventions

- Regrouper les tests par feature dans les deux cibles. Tester un cas d’usage avec un substitut de l’adaptateur quand il déclenche des effets système.
- Définir les critères de vérification dans la spec et les scénarios dans le plan. Le [guide technique](../INSTALL.md#tests-et-critères-de-vérification) décrit le jeu de référence et les durées d’enregistrement.

## Run

- Les deux cibles du modèle fournissent des exemples. Les tests métier prennent forme avec la feature et s’exécutent via le MCP officiel au moment de l’assert.
