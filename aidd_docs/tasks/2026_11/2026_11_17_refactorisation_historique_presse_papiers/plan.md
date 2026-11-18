---
objective: "Séparer les quatre responsabilités ciblées de l’historique, avec des effets substituables et les comportements, archives et performances existants préservés."
status: implemented
---

# Plan: Séparer les responsabilités de l’historique

Source: [Spec validée dans le chat](spec.md), [cadrage approuvé](brainstorm.md) et [audit d’architecture](../2026_11_17_audit/architecture.md).

## Phases

| # | Phase | File | Depends on |
| --- | --- | --- | --- |
| 1 | Fixer le filet de régression et les prérequis de mesure | [phase-1.md](phase-1.md) | none |
| 2 | Isoler les effets du cas d’usage de collage | [phase-2.md](phase-2.md) | 1 |
| 3 | Extraire la collecte et sa coordination avec les restitutions | [phase-3.md](phase-3.md) | 1, 2 |
| 4 | Injecter le rendu et isoler la zone d’aperçu des cartes | [phase-4.md](phase-4.md) | 2, 3 |
| 5 | Vérifier les parcours, les performances et les repères du projet | [phase-5.md](phase-5.md) | 1, 2, 3, 4 |

## External sources

| URL | What it settled |
| --- | --- |
| [Apple · Observation dans une vue](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app#Observe-model-data-in-a-view) | Documentation consultée via le MCP Xcode. Une dépendance est créée par les propriétés effectivement lues pendant le body, y compris au travers d’une propriété calculée. Déplacer la lecture de activeID dans la sous-vue, sans découper arbitrairement tout le modèle observable. |
| [Apple · Gestion de l’annulation](https://developer.apple.com/documentation/swift/withtaskcancellationhandler(operation:oncancel:)) | Documentation consultée via le MCP Xcode. Le handler est synchrone et peut s’exécuter concurremment. Conserver le relais vers la tâche de rendu et les contrôles de publication ; ne pas confondre demande d’annulation et fin effective du travail. |
| [Apple · Tests asynchrones](https://developer.apple.com/documentation/testing/testing-asynchronous-code) | La documentation Testing n’est pas installée dans le moteur documentaire Xcode de cet hôte ; l’article Apple a été consulté sur le site officiel. Les confirmations comptent les événements pendant leur corps, qui doit attendre le travail testé. Le skill Apple modernize-tests complète ces règles : Swift Testing pour la logique, XCTest conservé pour XCUIAutomation et état isolé par test. |

## Impact

| Category | Verdict and evidence | Handled in |
| --- | --- | --- |
| Runtime | Hôte observé sous macOS 27.2.1, Xcode 27.2 build 27B52. Le MCP répond aux recherches documentaires. L’audit de ce même code a compilé l’app et les cibles de test ; il n’a pas exécuté les tests. Les autorisations d’automatisation et de capture de la fenêtre de mesure restent à confirmer dans cette exécution. | 1, 5 |
| Runtime | macOS 26 reste retenu par hypothèse selon l’accord déjà consigné ; aucun nouvel hôte n’est requis pour ce chantier. Une compilation ne sera pas présentée comme une preuve d’exécution sur 26. | 5 |
| Regression | Risque élevé : le collage et le nettoyage partagent actuellement isPasting, les compteurs et une tâche de nettoyage. ⌘A à froid dépend encore de la présence de collectionTask. Les 103 tests du dernier assert sont documentés, pas relancés pendant le plan. Filet de sécurité avant extraction : oui. | 1, 2, 3, 5 |
| Regression | La file d’aperçus conserve deux jobs jusqu’à leur fin, même après annulation. Son cache évince les seules cartes non visibles au-delà de 48 résultats ou 24 Mio de PNG. La sous-vue doit préserver les branches, le cadrage, la couleur et les identifiants accessibles. | 4, 5 |
| Architecture | L’état UI construit des adaptateurs et possède le cycle de collecte ; le cas d’usage de collage importe AppKit et les moteurs sont fixés dans la file UI. Le plan déplace l’assemblage dans App, extrait un coordinateur de collecte et introduit seulement les opérations substituables nécessaires. Une cible et un processus sont conservés. | 2, 3, 4 |
| Documentation | Ajouter run.md pendant l’exécution pour les preuves et limites. Actualiser codebase-map.md avec les nouveaux points d’assemblage et de collecte. Les specs validées et les anciens rapports restent inchangés. | 1, 5 |
| Contributor checks | CONTRIBUTING.md ne prescrit aucune commande de validation du code. Les exigences viennent de coding-assertions.md : BuildProject, RunAllTests ou RunSomeTests, puis RenderPreview. Les derniers asserts ajoutent git diff --check et le lint Swift strict ; xcrun swift-format lint --strict a été vérifié dans l’aide locale. | 5 |

## Rules

| Rule | Why it applies |
| --- | --- |
| [Architecture](../../../memory/architecture.md) et [guide technique](../../../INSTALL.md#architecture) | App assemble les dépendances. Les cas d’usage ne dépendent ni des vues ni des classes concrètes des adaptateurs. Les accès lourds restent hors de l’acteur d’interface. |
| [Assertions](../../../memory/coding-assertions.md) | Plan seulement à cette étape ; implémentation après validation. Build, suites et Previews via le MCP Xcode lors de l’assert, puis revue distincte. |
| [Tests](../../../memory/testing.md) | Doubles pour les effets, fixtures isolées pour les intégrations et mêmes bornes de mesure pour la recherche. Les nouvelles vérifications asynchrones attendent des événements, pas des délais arbitraires. |
| [Stockage](../../../memory/database.md) | Préserver le contrat du stockage, le format d’archive et les données existantes ; ne pas modifier l’adaptateur pour simplifier les tests du coordinateur. |
| [VCS](../../../memory/vcs.md) | Une seule copie de travail. L’implémentation utilisera une branche refactor depuis main dans ce dossier. Aucun commit, push, PR ou fusion sans le go correspondant. |

## Decisions

| Decision | Why |
| --- | --- |
| Un coordinateur CollectClipboardHistory possède la collecte et la réservation des restitutions. | Les déplacer dans deux propriétaires indépendants ouvrirait une course entre nettoyage et préparation du collage. L’état UI conserve les recherches, la sélection, la présentation et la traduction des motifs en messages. |
| La réservation du collage est acquise avant tout await et libérée sur tous les chemins. | Elle attend le nettoyage déjà commencé et invalide un nettoyage en attente devenu obsolète, tout en laissant la capture de nouvelles copies continuer. |
| App lie les cibles AppKit aux opérations de collage et assemble les adaptateurs existants. | Le cas d’usage reçoit trois effets limités : écriture conditionnelle, contrôle du compteur et envoi. Il n’expose plus NSRunningApplication et ne reconstruit pas une cible à partir d’un PID plus tard. |
| Injecter une seule opération de rendu ; garder la lecture de source, la file et le cache dans ClipboardPreviewRequests. | La frontière suffit à fournir des résultats contrôlés sans déplacer les moteurs ni créer un service supplémentaire. La tâche détachée et son relais d’annulation restent à la frontière de rendu. |
| Extraire une sous-vue privée dans le fichier de carte existant. | Une frontière SwiftUI ne nécessite pas un nouveau fichier. Cela conserve aussi la visibilité des aides de couleur et de symbole. |
| Aucun changement de schéma, d’archive ou de moteur média. | Les contrats actuels suffisent ; les tests d’intégration restent le filet sur les données et les décodeurs réels. |
