# Rapport de validation — `Soutenance_Stage_ENSI_Final.pptx`

Fichier final : **`Soutenance_Stage_ENSI_Final.pptx` à la racine du dépôt**. Export PDF de secours : `deliverables/final-defense/Soutenance_Stage_ENSI_Final.pdf`.

Environnement de contrôle : python-pptx 1.0.2, LibreOffice 24.2.7.2 (rendu PPTX → PDF → PNG), Poppler.
Le fichier n'a **pas** été ouvert dans Microsoft PowerPoint (indisponible ici).

## 1. Intégrité du fichier — validé

| Contrôle | Résultat |
|---|---|
| Archive ZIP / OOXML valide | OK (`testzip` sans erreur ; relu par python-pptx et LibreOffice) |
| Format | 16:9, 13,333 × 7,5 in, identique sur les 18 diapositives |
| Nombre de diapositives | 16 principales (dont « Merci ») + 4 de secours (A–D) |
| Éléments éditables | Texte, tableaux, schémas et barres : formes natives, aucun schéma aplati en image |
| Images | 11 images, toutes embarquées (aucun lien externe), toutes avec texte alternatif |
| Débordement | Aucune forme hors de la diapositive (contrôle automatique des coordonnées) |
| Notes | Présentes sur les 18 diapositives ; les 14 principales ont durée, texte oral, transition et questions probables |
| Polices | Arial (déclarée aussi dans le thème) ; Courier New pour les identifiants de code. Rendu LibreOffice : Liberation Sans / Mono, métriquement équivalentes |
| Export PDF de secours | `Soutenance_Stage_ENSI_Final.pdf`, 18 pages |

## 2. Contrôle visuel — validé sur rendu LibreOffice

Les 18 diapositives ont été rendues en PNG et regardées une à une, puis corrigées et rendues de nouveau (trois itérations).

**Défauts trouvés et corrigés :**
- diapo 1 : titre sur trois lignes qui chevauchait le sous-titre ;
- toutes les diapos : ombres héritées du style du thème sur les formes ;
- diapo 6 : en-têtes de boîtes qui débordaient sur leur description ;
- diapo 8 : libellés de la machine à états qui se chevauchaient, note superposée aux seuils ;
- diapo 10 : légendes des captures qui empiétaient sur le pied de page ;
- diapo 11 : barres qui sortaient de la marge droite ;
- diapo 3 : coupures de ligne peu lisibles ;
- partout : guillemets français isolés en fin de ligne (espaces insécables ajoutés).

**État final :**
- aucun texte coupé ;
- aucun chevauchement involontaire ;
- marges de 0,6 in respectées ;
- captures non déformées (proportions d'origine) ;
- compositions variées : tableau, schéma de flux, matrice, machine à états, captures, chiffres clés, liste de limites.

**Contraste (WCAG, calculé, pas estimé à l'œil) :**

| Couleur | Sur blanc | Sur panneau EEF2F6 |
|---|---|---|
| Bleu nuit 1F3A5F | 11,5:1 | 10,2:1 |
| Texte 1B2530 | 15,5:1 | 13,8:1 |
| Gris secondaire 5B6B7A | 5,5:1 | 4,9:1 |
| Orange B84A12 | 5,2:1 | 4,6:1 |
| Bleu 2E75B6 | 4,8:1 | 4,3:1 |

Le bleu 2E75B6 n'est utilisé sur panneau qu'en gras ≥ 18 pt (seuil « grand texte » 3:1).

Le couple bleu/orange du graphique de la diapo 11 passe le validateur de palette : séparation daltonisme ΔE 22,6, contraste ≥ 3:1. Les segments sont étiquetés directement.

**Tailles de police :** corps et étiquettes 16–20 pt ; titres 28 pt ; chiffres clés 34–60 pt. Les tailles 11–12 pt ne servent qu'au pied de page, au repère de section, aux légendes et aux sources.

## 3. Contrôle factuel — validé contre le rapport (et le code)

Chaque valeur affichée a été recoupée avec le rapport ; les seuils l'ont aussi été avec le code.

| Diapo | Affirmations | Source |
|---|---|---|
| 1 | Stage d'été, Codingaholic La Marsa, encadrant Jendoubi Mohamed Khalil, 2025/2026 | Couverture, résumé, §1.1.1 |
| 2 | Défauts de la photo libre, problématique, KYC | Introduction, §1.1.2–1.1.3 |
| 3 | 5 fonctions, < 100 ms, ≥ 90 %, ≈ 2 s, Android + iOS, 6 semaines | §1.1.3, §2.2–2.3 |
| 4 | Tableau des trois options, Vision/VisionKit écarté | §1.3, tab. 1.2 |
| 5 | Couches et modules | §2.6.1, annexe A ; vérifié dans `lib/features/*` |
| 6 | Pipeline, 0,66/1,33, 0,65, 0,8/0,2, 0,30, ±20 %, 75 %, 856 × 540, isolate | §4.2, tab. 5.1 ; `document_contour_detector.dart`, `card_quad_geometry.dart` |
| 7 | Fond clair, moyenne vs médiane, CLAHE, réglage des seuils, gain non chiffré | §4.3 |
| 8 | États, 120, [60 ; 225], 12 %, 2,5 %, 3 frames, maintien 2 frames, contrôle de contenu | §5.2, tab. 5.1 ; `autocapture_viewmodel.dart` |
| 9 | Haar pré-entraîné, 4 rotations, corrélation 0,6, [150 ; 4 000], Hough, vote, anti-doublon | §6.2 |
| 10 | Vérification, recadrage, rotation, A4 2480 × 3508, export galerie, historique | §7.2.2, §8.2 |
| 11 | 177/177, 21/28 fichiers, paliers 15/6/7, fichiers non exécutés | §9.1, tab. 9.2 |
| 12 | 92–100 ms, 92 %, ≈ 2 s, méthode de mesure | Tab. 9.4, §2.3 |
| 13 | Timeout non implémenté, pas de vivacité ni de rejeu, couverture non mesurée | §7.2.3–7.2.4, conclusion générale |
| 14 | Synthèse et perspectives | Conclusion générale |

**Répartition par palier (diapo 11).** Les exécutés par palier (A : 11/15, B : 5/6, C : 5/7) sont déduits de la liste des sept fichiers absents donnée au §9.1, p. 50. La somme fait bien 21.

- Aucune métrique, capture ou résultat inventé.
- Les schémas de la diapo 2 sont étiquetés « illustratifs ».
- Les captures sont celles des decks existants, déjà masquées dans les pixels. Elles sont légendées pour ce qu'elles montrent : silhouettes de guidage, pas des détections.

Écarts rapport ↔ code : voir `Audit_Synthese.md` §4. Aucun n'est contredit par le deck.

## 4. Timing — estimé, non mesuré

| Durée prévue | Texte oral | Rythme | Marge sur 15 min |
|---|---|---|---|
| 13 min 55 | ≈ 1 850 mots (diapos 1–14) | ≈ 140 mots/min | ≈ 1 min |

Les durées et les temps cumulés figurent en tête de chaque note. Il s'agit d'une estimation par comptage de mots : le chronométrage à voix haute reste à faire.

## 5. Limites de cette validation

- Pas de test dans **Microsoft PowerPoint**, ni sur le vidéoprojecteur de la salle. Le rendu peut différer légèrement des métriques Liberation, même si Arial est métriquement équivalente.
- La suite **`flutter test`** n'a pas pu être relancée : pas de SDK Flutter ici. Les chiffres de tests sont ceux du rapport.
- **Aucune vidéo de démonstration** n'existe dans le dépôt : la démonstration reste à préparer, en direct ou en vidéo.
- La traçabilité des mesures (appareil, nombre de cartes et d'essais) n'existe pas dans le rapport. Elle ne pouvait donc pas être ajoutée.

## 6. À faire par l'étudiant avant le jour J

1. Ouvrir le PPTX dans PowerPoint, le faire défiler en mode présentation et vérifier les notes.
2. Facultatif : ajouter la date de soutenance et l'encadrant ENSI en diapositive 1 (absents du rapport, donc non inventés).
3. Retrouver le modèle de téléphone et le nombre d'essais des mesures de la diapo 12. Si iOS a été testé, mettre à jour les diapos 13 et 14.
4. Si possible, relancer `flutter test --reporter expanded --coverage` et mettre à jour les diapos 11 et B.
5. Enregistrer une courte vidéo de l'autocapture (cadre rouge → vert → capture), en copie locale, comme plan B de la démo de la diapo 10.
6. Répéter à voix haute avec un chronomètre (objectif ≤ 14 min).

## 7. Révision 2 — contrôles refaits

- Rendu des 19 diapositives et inspection visuelle. Correction des débordements des diapos 3 et 10 ; remplacement du symbole ✓, absent d'Arial.
- Contrôle automatique : aucune forme hors cadre, texte alternatif sur toutes les images, notes sur toutes les diapositives. Aucune occurrence de « 21/28 », « non exécuté », « non mesuré », « non chiffré », « non consigné », « Source » sur les diapositives.
- Timing : 14 min 00 prévues (cumuls dans les notes).
- La validation iOS est une information de l'auteur, non documentée dans le rapport (voir Audit_Synthese §6).

## 8. Révision 3

- **Nouvelle diapo 3 (parcours Avatar-ID)** : rendue et inspectée, coupure de mot corrigée.
- **Diapos 14, 15 et secours C** : re-rendues après mise à jour.
- **Contrôle automatique** : 20 diapositives, aucune forme hors cadre, notes partout.
- **Timing** : 14 min 30 prévues.

## 9. Révision 5 — animations

- **Transition** : fondu discret sur les 20 diapositives.
- **Apparitions en fondu au clic (0,4 s)** sur 5 diapositives, 10 clics au total :
  - parcours Avatar-ID (2) ;
  - pipeline (1) ;
  - difficulté fond clair (3) ;
  - autocapture (1) ;
  - mesures (3).
- **Consignes de clic** ajoutées en tête des notes de ces diapositives.
- **Vérifications** : identifiants de cibles existants, identifiants de minutage uniques, ordre XML conforme (cSld, clrMapOvr, transition, timing). L'import LibreOffice (conversion en ODP) retrouve les 10 étapes au clic.
- **Non vérifié** : la lecture dans PowerPoint. Faire défiler une fois le diaporama avant la soutenance.
- **Export PDF** : il montre l'état final de chaque diapositive (sans animation).

## 10. Révision 6 — construction progressive sur toutes les diapositives

- **Apparition automatique** à l'ouverture de chaque diapositive (pas de clic) : le titre d'abord, puis le contenu par bandes, de haut en bas.
  - Chaque bande dure 0,35 s ; une nouvelle bande démarre toutes les 0,25 s.
  - Au plus 7 étapes par diapositive, soit environ 1,5 s.
  - Un cadre et son contenu apparaissent ensemble ; la machine à états (diapo 9) apparaît d'un bloc.
- **Clics** : les 10 étapes au clic des diapos 2, 7, 8, 9 et 13 sont conservées après la construction automatique.
- **Contrôles** :
  - XML valide sur les 20 diapositives : cibles existantes, identifiants uniques.
  - Rendu des états intermédiaires des diapos 2, 3, 4, 5, 6, 7, 9, 11, 13 et 15 pour vérifier l'ordre d'apparition.
  - L'import LibreOffice reconnaît les séquences.
- **Non vérifié** : la lecture dans PowerPoint.

## 11. Révision 7 — apparitions au clic, choisies par l'orateur

- **Construction automatique supprimée** (`AUTO_BUILD = False` dans le script).
- **Apparitions au clic (fondu, 0,4 s)** sur les 14 diapositives de contenu, 38 clics au total. Le titre et les éléments de repère sont visibles dès l'arrivée sur la diapositive.
- **Sans clic** : la diapo de titre, la diapo « Merci » et les 4 secours, pour un affichage immédiat pendant les questions.
- **Notes** : chaque diapositive animée commence par une ligne « ANIMATIONS — N clics : … » qui décrit l'ordre.
- **Contrôles** :
  - XML valide ;
  - états avant/après chaque clic rendus pour les diapos 3, 10 et 15 ;
  - LibreOffice reconnaît les 38 étapes au clic.

## 12. Révision 8 — discours compacté pour 10 minutes maximum

- **Diapositives inchangées** : seuls les textes oraux et les transitions des notes ont été réécrits.
- **Volume** : environ 770 mots (contre environ 2 000), soit environ 6 min de parole à 130 mots/min.
- **Créneaux** : 8 min 00 au total, clics et respirations compris, ce qui laisse environ 2 min de marge sous les 10 min (ou une démonstration en direct en diapo 11).
- **Repères de clic** : un marqueur « [clic] » dans le texte oral indique le moment exact de chaque clic.
- **Préparation aux questions** : les questions probables et leurs réponses sont conservées ; elles ne sont pas lues.
