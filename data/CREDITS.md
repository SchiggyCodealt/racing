# Credits for data

## The grand-prix circuits (version 6.28.0)

The shapes of the Monaco, Silverstone and Spielberg tracks (`tools/gen_tracks.gd`, written into
`data/tracks.json`) are traced from the circuit centre lines of
[bacinger/f1-circuits](https://github.com/bacinger/f1-circuits) (`mc-1929`, `gb-1948` and `at-1969`): each line was
split into straights and turns and their lengths and radii fitted to it. The data set's licence:

```
MIT License

Copyright (c) 2019-2025 Tomislav Bacinger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The game uses the circuits' shapes only, named by their places; it carries no circuit, event or sponsor names
or logos.

## Le Mans (version 6.33.0)

The Le Mans track uses no outside data: it is laid out by hand in `tools/gen_tracks.gd` from the real circuit's
well-known corners (Dunlop, the esses, Tertre Rouge, the Mulsanne straight and its two chicanes, Mulsanne corner,
Indianapolis, Arnage, the Porsche curves, the Ford chicanes) and its published lap length (13.626 km).
