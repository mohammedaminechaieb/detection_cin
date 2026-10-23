# Régénérer le support

```bash
pip install python-pptx==1.0.2
python3 deliverables/final-defense/build/build_deck.py
# rendu de contrôle (facultatif)
soffice --headless --convert-to pdf --outdir /tmp Soutenance_Stage_ENSI_Final.pptx
```

- `build_deck.py` : contenu, mise en page et notes de présentation, tout dans un seul script.
- `assets/` : logos et captures d'écran masquées, repris tels quels des decks existants. Les gabarits logo/drapeau sont lus dans `assets/templates/` à la racine du dépôt.
- Toute modification de contenu doit rester conforme à `Rapport_CIN.pdf` (voir `../Audit_Synthese.md`).
