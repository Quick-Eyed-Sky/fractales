# Fractales: explore fractals on a Mac, fast and deep

<a id="english"></a>
**English** · [Version française plus bas ↓](#francais)

**A small native Mac app, free and open source, for wandering through fractals.**
The computation runs on the graphics processor of Apple chips (M1, M2, M3, M4…) with Metal,
and zooms go down to ×10³⁰ without the picture breaking up into blurry pixels.

> Work in progress: the rendering engine is here; infinite automatic zoom, 4K export and the
> colour editor come next.

## What it does

- **Five formulas**: Mandelbrot, Burning Ship, Tricorn, Multibrot z³, Celtic, and for each one
  **the Julia set** of any point (⌥-click on the picture, or the J key).
- **Ready-made figures**: Seahorse Valley, Douady's rabbit, the Burning Ship armada…
- **Smooth navigation**: drag or two fingers to move, pinch or scroll wheel to zoom under the
  pointer, double-click for an animated ×3 zoom. While moving, the picture is computed at half
  resolution to keep up, then recomputed at full resolution as soon as it stops.
- **Deep zooms** down to ×10³⁰ (see [How it works](#how-it-works)).
- **Six palettes**, with adjustable density and offset; changing the colours does not restart
  the computation.

## In English and French

The app speaks French on a Mac set to French, and English on a Mac set to English (or to any
other language). To see it in the other language without changing your Mac's: System Settings ›
General › Language & Region › Applications, + button, choose Fractales and the language.
Or, from the Terminal:

```
open Fractales.app --args -AppleLanguages '(fr)'
```

The English texts are in `source/en.lproj/Localizable.strings`; the French texts are written
directly in the code. `tests/check_strings.py` checks that no text was left untranslated.

## Building the app

You only need Apple's command line tools (not the full Xcode):

```
xcode-select --install
cd fractales/source
./build_app.sh
```

`Fractales.app` appears in the `fractales` folder. macOS 14 or later, Apple chip.

## How it works

The graphics processor only computes with 32-bit floating-point numbers, which run out of
digits beyond a zoom of ×100,000. So Fractales uses **perturbation**: a single point of the
picture (the reference) is computed on the main processor with as many digits as needed (up to
144 digits, `FractalCore.c`), and for each pixel the GPU only computes the tiny difference from
that reference, which fits in 32 bits at any zoom (`Shaders.metal`). When that difference
becomes badly conditioned, the pixel is "rebased" onto an orbit starting from 0 (Zhuoran's
method), which avoids the usual perturbation artefacts.

| File | Role |
|---|---|
| `source/FractalCore.c` | high-precision fixed-point numbers, reference orbits |
| `source/Shaders.metal` | per-pixel computation (perturbation) and colouring, compiled at launch |
| `source/Renderer.swift` | Metal control: orbits, textures, half resolution while moving |
| `source/FractalModel.swift` | view state: formula, high-precision centre, zoom, palettes |
| `source/CanvasView.swift` | mouse, trackpad, keyboard |
| `source/FractalesApp.swift` | window and settings panel (SwiftUI) |

## Tests

`tests/run_tests.sh` runs the GPU kernel on the main processor and compares each picture with a
direct 113-bit computation, for the five formulas and Julia, from the whole view down to a zoom
of ×10²⁸. It runs on Linux (gcc + libquadmath), and on every push to GitHub along with building
the app on a Mac (GitHub Actions).

## Licence

MIT, see [LICENSE](LICENSE).

---

<a id="francais"></a>
# Fractales : explorer les fractales sur Mac, vite et profond

[↑ English version above](#english) · **Français**

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
- **Zooms profonds** jusqu'à ×10³⁰ (voir [Comment ça marche](#comment-ça-marche)).
- **Six palettes**, avec densité et décalage réglables ; changer les couleurs ne relance pas le
  calcul.

## En français et en anglais

L'appli parle français sur un Mac réglé en français et anglais sur un Mac réglé en anglais (ou
dans toute autre langue). Pour la voir dans l'autre langue sans changer celle du Mac : Réglages
Système › Général › Langue et région › Applications, bouton +, choisir Fractales et la langue.
Ou, depuis le Terminal :

```
open Fractales.app --args -AppleLanguages '(en)'
```

Les textes anglais sont dans `source/en.lproj/Localizable.strings` ; les textes français sont
directement dans le code. `tests/check_strings.py` vérifie qu'aucun texte n'a été oublié.

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
