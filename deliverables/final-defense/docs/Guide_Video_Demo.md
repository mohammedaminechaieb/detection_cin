# Vidéo de démonstration : tournage, floutage et intégration

## 1. Où la placer dans la soutenance

- **Sur sa propre diapositive**, la **diapo 12 « Démonstration »**, déjà prévue dans le support : après le recto/verso (diapo 10) et le post-traitement (diapo 11). La vidéo montre alors tout le parcours en une fois, comme une synthèse, avant les tests et les résultats.
- **Commenter pendant la vidéo**, ni avant ni après : le texte prévu dans les notes (environ 40 s) suit les étapes à l'écran.
- Durée visée : **30 à 45 s**. Plus long, c'est autant de temps pris aux résultats.

## 2. Que filmer (scénario de 40 s)

1. Écran recto : cadre **rouge**, puis approche de la carte → cadre **vert**, messages de qualité (« Ne bougez plus… »).
2. Capture automatique du recto (vibration), puis passage automatique au **verso**.
3. Verso : détection, puis capture automatique.
4. Arrivée sur l'écran **Vérification** (2 à 3 s suffisent).

**Conseils de tournage**
- Filmer avec l'**enregistreur d'écran** du téléphone (Android : Enregistrement d'écran ; iOS : Centre de contrôle → Enregistrement de l'écran), pas avec une autre caméra.
- Choisir un bon éclairage, un fond uni, la carte tenue à plat.
- Faire 3 ou 4 prises et garder la plus fluide.

## 3. Masquer les données de la carte

> Règle : **aucune donnée personnelle lisible** dans la vidéo (photo, nom, numéros, date, adresse, code-barres, empreinte).

**Pourquoi on ne peut pas simplement tout cacher avant de filmer.** L'application a besoin de certains éléments pour reconnaître chaque face :
- au **recto** : le **visage**, le **logo** et le **drapeau** ;
- au **verso** : le **code-barres**, l'**empreinte** et la **ligne de séparation**.

Si on les cache physiquement, la détection échoue.

### Méthode recommandée (deux étapes)

**Étape A — avant de filmer**, cacher **uniquement le texte** (nom, prénom, numéros, dates, adresse) avec des **petits morceaux de papier opaque** ou du ruban adhésif mat. Laisser le visage, le logo, le drapeau, le code-barres, l'empreinte et la ligne visibles. *(Ou utiliser une carte factice au format ID-1 avec des données fictives, comme le propose l'annexe C du rapport.)*

**Étape B — après le tournage**, flouter ce qui reste sensible (le visage, le code-barres et l'empreinte) avec un **flou qui suit la carte** (*tracking*) :

| Outil (gratuit) | Comment faire |
|---|---|
| **CapCut** (téléphone ou PC) | Importer la vidéo → **Effets** → *Flou* ou *Mosaïque*. Placer le rectangle sur la zone, puis activer **Suivi** (*Tracking*) pour qu'il suive la carte. Répéter pour chaque zone. |
| **DaVinci Resolve** (PC) | Page **Color** → **Window** (rectangle) sur la zone → **Tracker** (analyser en avant). Dans **Blur**, augmenter le *Radius*. Un nœud par zone. |
| **Shotcut / Kdenlive** (PC) | Filtre **Blur: Pad/Box** + **Mask: Simple shape**, avec des images clés si la carte bouge. Plus manuel, mais suffisant si la carte bouge peu. |

### Variante rapide si la carte bouge peu (ffmpeg)

Si la carte reste presque immobile dans une zone connue, flouter un rectangle fixe. Les valeurs x, y, w, h (position et taille en pixels) se mesurent sur une capture de la vidéo :

```bash
ffmpeg -i demo_brute.mp4 -filter_complex "[0:v]crop=w=300:h=380:x=120:y=900,boxblur=20[f];[0:v][f]overlay=120:900" -c:a copy demo.mp4
```

### Avant d'utiliser la vidéo
- La regarder **image par image** aux moments de capture : aucun texte ni code ne doit être lisible.
- Vérifier aussi l'écran **Vérification** à la fin : les images capturées y apparaissent en grand.

## 4. Intégrer la vidéo dans le PowerPoint

**Option 1 (automatique)**
1. Exporter la vidéo en **MP4 (H.264)**, sous 50 Mo de préférence.
2. La nommer `demo.mp4` et la placer dans `deliverables/final-defense/build/assets/`.
3. Relancer `python3 deliverables/final-defense/build/build_deck.py`.

La vidéo remplace automatiquement le cadre de la diapo 12.

**Option 2 (dans PowerPoint)**
1. Diapo 12 → supprimer l'image du cadre.
2. **Insertion → Vidéo → Cet appareil**, puis redimensionner dans le cadre.
3. Onglet **Lecture** → *Démarrer* : **Automatiquement** (ou *Au clic*).

**Le jour J**
- Garder aussi une **copie de la vidéo sur clé USB**.
- Tester la lecture sur le PC de la salle.
- Si la vidéo ne se lance pas, revenir aux captures de la diapo 11 et dire : « Je vous montre le parcours sur ces captures. »
