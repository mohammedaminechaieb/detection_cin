# Audit et synthèse — soutenance de stage CIN / Avatar-ID

Ce fichier documente comment a été construit le support définitif `Soutenance_Stage_ENSI_Final.pptx`. Il recense les sources lues, compare les trois versions existantes, statue sur chaque recommandation de l'audit externe et décrit la structure finale.

## 1. Sources et hiérarchie appliquée

| Rang | Source (dans le dépôt, non modifiée) | Usage |
|---|---|---|
| 1 | `Rapport_CIN.pdf` (61 p.) | Seule référence pour les faits, chiffres, résultats et limites |
| 2 | `Avatar-ID — Soutenance de stage.pptx` (deck A) · `Avatar-ID — Soutenance de stage1.pptx` (deck B) · `soutenance_avatarid_final.pptx` (deck C) | Contenus, captures, structures et pistes visuelles |
| 3 | `Audit de la soutenance CIN Avatar-ID.pdf` (34 p.) | Constats et recommandations, évalués un par un |
| — | Code du dépôt (`lib/`, `test/`, `assets/`) | Contre-vérification des valeurs et du vocabulaire ; jamais utilisé pour ajouter une affirmation absente du rapport |

L'audit externe n'avait pas accès au code. Ce travail l'a eu, ce qui a permis de vérifier les 20 seuils du tableau 5.1 dans les fichiers sources (tous conformes) et de relever les écarts du §4.

## 2. Comparaison des trois versions

| | Deck A (16 diapos) | Deck B (23 diapos) | Deck C (18 diapos, audité) |
|---|---|---|---|
| Nature | Maquette typographique | Version longue de C | Version de travail la plus aboutie |
| Exactitude | Bonne, mais « stage de fin d'études » (le rapport dit **stage d'été**) | Idem C ; même erreur sur le type de stage | Bonne ; placeholder en page de titre ; même erreur |
| Contenu | Titres-sujets, aucune capture, aucune note | Sommaire, architecture globale, toutes les captures, notes sur 17 diapos | Titres-affirmations, captures masquées, notes complètes |
| Narration | Claire (sommaire en 5 parties) mais sans preuve | Redondances (technologies + choix, aperçu + démo) | Fluide ; diapos 10 et 11 redondantes |
| Visuel | Gris/bleu sobre, monospace, très petit texte | Mise en page cassée diapo 13, texte à 14 pt | Sobre mais répétitif ; Arial + Calibri ; 14 pt fréquent |
| Timing | Non évaluable (pas de notes) | Trop long (23 diapos) | 13 min 20 prévues |

**Repris de chaque version.**
- **C** : la colonne vertébrale (titres-affirmations, cibles → mesures → limites), les captures masquées dans les pixels et les réponses aux questions probables présentes dans les notes.
- **B** : la vue d'architecture et le sommaire en sections, transformés en repère de section discret en haut à droite.
- **A** : la retenue typographique et la numérotation des étapes.

Aucune diapositive n'a été recopiée telle quelle : les 18 diapositives ont été recomposées.

## 3. Recommandations de l'audit externe : décisions

Statuts : **Fait** (implémenté) · **Adapté** · **Impossible ici** (dépend d'une donnée ou d'un outil absents) · **Rejeté** (avec motif).

| ID | Recommandation | Décision | Comment |
|---|---|---|---|
| P0-01 | Placeholder date / encadrant ENSI | **Adapté** | Ligne supprimée : ni la date ni l'encadrant ENSI ne figurent dans le rapport. À ajouter si souhaité (voir Validation_Report §6). |
| P0-02 | Figures 7.1, 7.2, 8.1 du rapport partiellement lisibles | **Hors deck** | Ces figures ne sont pas utilisées. Seules des captures déjà masquées sont reprises. Le rapport n'a pas été modifié. |
| P1-01 | Appareil, n, conditions des mesures | **Adapté** | Inconnus dans le rapport. La diapo 12 le dit en clair (« non consigné »), et les notes indiquent quoi répondre. |
| P1-02 | Relancer `flutter test --coverage` | **Impossible ici** | Pas de SDK Flutter dans l'environnement. Les chiffres 177/177 et 21/28 sont conservés, avec la liste des 7 fichiers (secours B). |
| P1-03 | Vidéo de démonstration | **Impossible ici** | Aucune vidéo dans le dépôt. La diapo est retitrée en parcours utilisateur, et un créneau de démo en direct est prévu dans les notes. |
| P1-04 | Séparer OpenCV / développé ; Haar pré-entraîné | **Fait** | Légende primitive / conçu (diapo 6), mention « pré-entraînée, non entraînée sur la CIN » (diapo 9), secours D. |
| P1-05 | iOS non validé dans les limites | **Fait** | Limite n° 1 (diapo 13) et premier point « À faire » (diapo 14). |
| P1-06 | Correctif fond clair : trois correctifs, gain non chiffré | **Fait** | Diapo 7 : médiane + CLAHE + réglage des seuils, avec « gain non chiffré » en orange. |
| P1-07 | Architecture : un module type, couches réelles | **Fait** | Diapo 5 : module type avec flèches libellées et matrice modules × couches (annexe A du rapport). |
| P1-08 | « Intégré à Avatar-ID » à préciser | **Fait** | Sous-titre « module de capture pour Avatar-ID » ; notes : restitue deux `Uint8List` + page A4 (§8.2.5). |
| P1-09 | 92 % sans dénominateur | **Fait** | Réserve affichée ; réponse préparée sur le recouvrement réglage/test. |
| P2-01 | Problème : titre et définition KYC | **Fait** | Diapo 2, mention « schémas illustratifs ». |
| P2-02 | « ≈ 2 s au maximum » contradictoire ; objectifs fonctionnels absents | **Fait** | Diapo 3 : cinq fonctions + trois cibles ; formulation du rapport. |
| P2-03 | ML Kit : préciser Document Scanner ; ligne « effort de réglage » | **Fait** | Diapo 4. |
| P2-04 | Texte essentiel ≥ 16 pt | **Fait** | Corps 16–20 pt. 11–12 pt réservés au pied de page, au repère de section et aux sources. |
| P2-05 | Une seule famille de polices | **Fait** | Arial partout (définie dans le thème) ; Courier New pour les identifiants de code. |
| P2-06 | Orange = réserve uniquement | **Fait** | « Retenu » est marqué par le fond bleu nuit (diapo 4). |
| P2-07 | Fusionner aperçu et démo | **Fait** | Diapo 10 unique, trois captures de 4,5 in de haut. |
| P2-08 | Retirer le graphique des jours | **Fait** | Remplacé par Livré / Mesuré / À faire. |
| P2-09 | Notes à la 1ʳᵉ personne, script séparé des consignes | **Fait** | Structure fixe : ⏱ durée, TEXTE ORAL, TRANSITION, QUESTIONS PROBABLES. |
| P2-10 | Références | **Fait** | Secours D (bibliographie du rapport). |
| P2-11 | Machine à états avec retours ; écran annoté | **Fait** | Diapo 8 : retours « contrôle échoue » et « reset », règle « carte perdue ». |
| P2-12 | Tiers inférieur vide | **Fait** | Contenu réparti sur toute la zone utile (vérifié au rendu). |
| P2-13 | `jury_qa.md` cité mais absent | **Fait** | Plus aucune référence ; questions-réponses intégrées aux notes. |
| P3-01…08 | Finitions (terminal retapé, logos, seuils manquants, marqueurs, décimales, animations, test PowerPoint) | **Fait / adapté** | Plus de terminal retapé ; logos alignés ; les 20 seuils en secours A ; virgule décimale partout ; aucune animation ; test dans PowerPoint non réalisable ici. |
| Plan J | 14 diapos + secours A–E | **Adapté** | 14 + 4 secours : l'apport personnel (D) et les références (E) sont réunis en secours D. |
| Visuel K | Palette, grille, pied de page, repère de section | **Fait**, avec un écart | Titres à 28 pt au lieu de 32 pt, pour que les titres-affirmations tiennent sur deux lignes. |
| Règle ≤ 40 mots | — | **Adapté** | Respectée pour le texte courant. Les diapos-schémas (6, 8) dépassent à cause des étiquettes, ce qui est attendu par un jury d'ingénieurs. |

## 4. Écarts relevés entre le rapport, les decks et le code

| Sujet | Rapport | Code / autres sources | Traitement dans le deck |
|---|---|---|---|
| Type de stage | « stage d'été » (couverture, résumé) | Decks A, B et C : « stage de fin d'études » | Corrigé : « stage d'été » |
| Rejet des quadrilatères en bord d'image | §4.2.3 : « dont un coin touche le bord » | `touchesFrameBorder` rejette seulement si **tous** les coins sont près du bord | Formulation neutre : « collés au bord ». À corriger dans le rapport. |
| Passes de détection | « quatre passes » | Canny est appliqué avec deux fermetures morphologiques (`canny`, `canny_fin`), puis adaptatif, saturation et gradient | Conservé « quatre passes » (quatre familles), cohérent avec le rapport |
| Position du code-barres au verso | §6.2.3 : « du haut de la carte » | Recherche côté haut, puis correction finale de +180° (`back_orientation_detector.dart`) ; la silhouette de l'overlay le place en bas | Aucune position affirmée : « localisé, non décodé » |
| Garantie anti-fraude | §1.1.2 promet l'impossibilité d'une photo d'écran ; §7.2.4 la restreint | — | Le §7.2.4 est suivi (diapo 13, secours C) |
| Historique | §8.2.4 : « captures de la session » | `CaptureStorageService` conserve jusqu'à 20 captures sur l'appareil | Formulation : « historique conservé sur l'appareil » (secours C) |

## 5. Structure finale (14 + 4)

| # | Section | Titre-affirmation | Durée |
|---|---|---|---|
| 1 | — | Détection automatique et autocapture de la CIN tunisienne | 0:30 |
| 2 | Contexte | Une photo libre de CIN peut être floue, de travers ou envoyée deux fois | 0:50 |
| 3 | Contexte | Cinq fonctions à automatiser, trois cibles chiffrées, deux plateformes | 1:00 |
| 4 | Contexte | Seul OpenCV tenait Android + iOS en six semaines, sans jeu de données annoté | 0:55 |
| 5 | Conception | Un domaine sans Flutter ni OpenCV rend la logique testable sans caméra | 0:55 |
| 6 | Conception | Quatre passes de contours et un score géométrique retiennent le quadrilatère | 1:30 |
| 7 | Conception | Sur fond clair, la détection échouait ; médiane, CLAHE et réglage des seuils l'ont corrigée | 1:05 |
| 8 | Conception | La capture part seule après deux frames consécutives nettes, bien exposées et stables | 1:15 |
| 9 | Conception | Un visage et deux gabarits identifient le recto ; trois indices votent pour le verso | 1:10 |
| 10 | Résultats | Après les deux captures, l'utilisateur vérifie, ajuste et exporte chaque face | 1:15 |
| 11 | Résultats | 177 cas de test passent, sur 21 des 28 fichiers ; les cartes réelles restent testées à la main | 0:50 |
| 12 | Résultats | Les trois cibles sont atteintes de justesse, sur un échantillon encore restreint | 1:00 |
| 13 | Bilan | Cinq limites connues, à lever avant un usage en production | 0:50 |
| 14 | Bilan | Une capture recto/verso autonome livrée en six semaines ; prochaine étape : iOS et un jeu d'images | 0:50 |
| A | Secours | Tous les seuils sont empiriques ; la netteté 120 n'a de sens qu'à 856 × 540 px | — |
| B | Secours | 177 cas exécutés ne prouvent ni la couverture ni la validité sur cartes réelles | — |
| C | Secours | Ce que le module garantit sur la capture, et ce qu'il ne garantit pas | — |
| D | Secours | OpenCV fournit les primitives ; l'assemblage, les scores et la logique de capture sont développés (+ références) | — |

Total prévu : 13 min 55 à environ 140 mots/min, soit environ 1 min de marge sur 15 min.

**Test du deck fantôme.** Lus à la suite, les titres 2 à 14 racontent l'argument complet : problème → exigences → choix → architecture → pipeline → difficulté → autocapture → recto/verso → parcours → tests → mesures → limites → bilan.

## 6. Révision 2 — demandes de l'auteur (prioritaires sur §3 à §5)

- **iOS** : l'auteur confirme avoir testé l'application sur iOS, avec un comportement identique à Android. Le rapport ne le documente pas ; l'information vient de l'auteur. iOS sort des limites et apparaît comme résultat (diapos 3, 4, 12, 14).
- **Mentions restrictives retirées des diapositives** : 21/28 fichiers, fichiers non exécutés, couverture non mesurée, gain non chiffré, échantillon non consigné. Les réponses factuelles restent dans les notes (« QUESTIONS PROBABLES ») pour préparer les questions du jury.
- **Lignes de source et notes grises de bas de page supprimées.** Restent les légendes fonctionnelles : légende des couleurs, légendes des captures.
- **Diapo 13** : « limites » devient « quatre pistes vers la production » (jeu d'images, tests réels automatisés, timeout, vivacité et anti-rejeu).
- **Diapo 15 ajoutée** : « Merci pour votre attention ».
- **Contenus des secours intégrés aux diapos principales** :
  - pénalité ×0,85 et resserrement de 1,5 % (diapo 6) ;
  - paramètres Haar (diapo 9) ;
  - traitement sur l'appareil (diapo 10) ;
  - paliers de test détaillés (diapo 11) ;
  - apport personnel (diapo 14).
- **Secours** : B devient « méthodes de test par composant » (rapport, tableau 9.3) ; C est reformulé en « garanti / prochaines étapes ».
- **Structure finale** : 15 diapositives principales + 4 de secours, 14 min environ.
