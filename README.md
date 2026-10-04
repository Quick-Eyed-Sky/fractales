# Fractales : explorer les fractales sur Mac, vite et profond

**Une petite appli Mac native, gratuite et libre, pour se promener dans les fractales.**
Le calcul tourne sur le processeur graphique des puces Apple (M1, M2, M3, M4…) avec Metal,
et les zooms descendent jusqu'à ×10³⁰ sans que l'image se dégrade en pixels flous.

> Version de travail : le moteur de rendu est là ; le zoom automatique infini, l'export 4K et
> l'éditeur de couleurs arrivent ensuite.

## Ce qu'elle fait

- **Cinq formules** : Mandelbrot, Burning Ship, Tricorne, Multibrot z³, Celtique, et pour
  chacune **l'ensemble de Julia** de n'importe quel point (⌥-clic sur l'image, ou la touche J).
- **Des figures toutes prêtes** : vallée des hippocampes, lapin de Douady, l'armada du Burning
  Ship…
- **Navigation fluide** : glisser ou deux doigts pour se déplacer, pincer ou molette pour
  zoomer sous le pointeur, double-clic pour un zoom ×3 animé. Pendant le mouvement l'image est
  calculée en demi-résolution pour suivre, puis recalculée en pleine résolution dès l'arrêt.
- **Zooms profonds** jusqu'à ×10³⁰ (voir plus bas comment).
- **Six palettes**, avec densité et décalage réglables ; changer les couleurs ne relance pas le
  calcul.

## Construire l'appli

Il faut seulement les outils en ligne de commande d'Apple (pas Xcode complet) :

```
xcode-select --install
cd fractales/source
./build_app.sh
```

`Fractales.app` apparaît dans le dossier `fractales`. macOS 14 ou plus récent, puce Apple.

## Comment ça marche

Le processeur graphique ne calcule qu'en nombres à virgule de 32 bits, qui n'ont plus assez de
chiffres au-delà d'un zoom de ×100 000. Fractales utilise donc la **perturbation** : un seul
point de l'image (la référence) est calculé sur le processeur central avec autant de chiffres
que nécessaire (jusqu'à 144 chiffres, `FractalCore.c`), et le GPU ne calcule pour chaque pixel
que la minuscule différence avec cette référence, ce qui tient dans 32 bits à n'importe quel
zoom (`Shaders.metal`). Quand cette différence devient mal conditionnée, le pixel « rebascule »
sur une orbite qui part de 0 (méthode de Zhuoran), ce qui évite les artefacts classiques de la
perturbation.

| Fichier | Rôle |
|---|---|
| `source/FractalCore.c` | nombres en virgule fixe haute précision, orbites de référence |
| `source/Shaders.metal` | calcul par pixel (perturbation) et mise en couleurs, compilé au lancement |
| `source/Renderer.swift` | pilotage Metal : orbites, textures, demi-résolution pendant le mouvement |
| `source/FractalModel.swift` | état de la vue : formule, centre en haute précision, zoom, palettes |
| `source/CanvasView.swift` | souris, trackpad, clavier |
| `source/FractalesApp.swift` | fenêtre et panneau de réglages (SwiftUI) |

## Tests

`tests/run_tests.sh` exécute le noyau GPU sur le processeur central et compare chaque image à
un calcul direct en 113 bits, pour les cinq formules et Julia, de la vue d'ensemble jusqu'à un
zoom de ×10²⁸. Il tourne sous Linux (gcc + libquadmath), et à chaque envoi sur GitHub avec la
construction de l'appli sur un Mac (GitHub Actions).

## Licence

MIT, voir [LICENSE](LICENSE).
