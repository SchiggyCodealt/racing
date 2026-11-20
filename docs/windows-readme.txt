Track Rush 6.35.0 for Windows (64-bit)
======================================

A Trackmania-style racer with nine cars, twenty-three tracks (seven of them
with dirt or packed snow, four of them rally stages on gravel, sand, ice and
mud, three of them real grand-prix circuits, and Le Mans), medals, ghosts and an AI driver
you train yourself, with any of the cars. Medals and wins against five AI
opponents (Rookie to Elite) pay money and career points, and money buys cars
and upgrades. The tracks open one at a time: you start with Rookie Oval, and
a bronze medal or better on a track, with any car, opens the next one for
good.

New in 6.35.0: the aero tune. Once a car's weight upgrade is at level 5,
its seventh part opens: an aero tune with five levels, each 6 % less drag
(level 5: 30 % less) and a longer top gear, for a higher top speed: about
12 % more at level 5 (the Racer 278 to 312 km/h). Like the supercharger,
each level is fitted with the trial of arrows; a miss fits nothing and
half the price comes back.

Earlier versions, newest first:
6.34.0  the supercharger: once the engine is at level 5, five levels of +6 %
        power each, each fitted with a trial: press a row of arrows in order
        before the bar runs out (4 to 8, faster every level); a miss gives
        half the price back.
6.33.0  Le Mans (track 23, 13.63 km a lap) and endurance races: Race the
        field on a circuit for 10, 20, 30 or 40 laps with ten cars, the
        chequered flag, a pause on Esc, pay by place.
6.32.0  top 10s: every track keeps its ten fastest laps and the ten fastest
        times through each sector, by any car; a time that makes a list
        earns career points by its place (25 for 1st down to 1); R on the
        menu shows them.
6.31.0  your nitro is back in Race the AI (the AI car still has none);
        Race the field and the cups stay without nitro.
6.30.0  more ways to earn money: $1 for every millisecond under the author
        time, once per track and car (a faster run later pays the extra),
        and $1 for every 100 points of a run's score, every run.
6.29.0  a ninth car, the Sarthe: a Le Mans prototype, a hybrid with the
        highest top speed, $50,000; the car page three cards to a row.
6.28.0  three real grand-prix circuits, tracks 20 to 22: Monaco (3.35 km,
        a harbour town), Silverstone (5.85 km) and Spielberg (4.28 km),
        two laps each, and a seventh cup, the Grand Prix Cup.
6.27.0  no barriers on the eleven tracks with loose ground: cones along
        both edges (0.5 s each knocked over) and a gravel-trap run-off;
        no checkpoint gates or CP counter; the minimap at the top left and
        the timing tower at the top right.
6.26.0  a minimap with three sectors, S1 to S3, in the way of the F1 games:
        the sector you are in, the ones done this lap (green when the
        fastest yet) and every car as a dot; on the menu, R (or Records)
        shows the fastest time through each sector of every track, by any
        car, with the car and its upgrades.
6.25.0  faster, closer AI opponents: every level a step faster (the Elite
        flat out, 3-11 % under the author time), every AI car at upgrade
        level 3, a field 4 % from the slowest car to the fastest, and two
        new drivers in the Apex and the Quadra.
6.24.0  an eighth car, the Quadra: a boxy 1980s all-wheel-drive rally coupe
        with a five-cylinder turbo, the quickest on snow, ice and gravel;
        $26,000, with its own sound, medal times, upgrades and opponents.
6.23.0  four rally stages, tracks 16 to 19: Pine Ridge (gravel), Dune Sea
        (sand), Frozen Lake (ice) and Monsoon Trail (mud), point-to-point
        sprints with their own textures and scenery, and a sixth cup, the
        Rally Cup; fixed a fault when braking over a crest on loose ground.
6.22.0  a seventh car, the Apex: an open-wheel formula car with wings, the
        quickest on most asphalt tracks and the slowest on loose ground;
        $40,000, with its own V10 sound, medal times, upgrades and opponents.
6.21.0  a fifth upgrade, Weight: every level makes the car 3 % lighter (level
        10 about a fifth), so it pulls harder, stops shorter and gets more out
        of the nitro; the fifth chip on the car page (key 5).
6.20.0  a leaderboard in the way of the F1 games: a timing tower on the left
        in Race the field and the cups (place, colour, three-letter code, gap
        to the leader; rows slide, green and red arrows), and results and
        championship tables as rows of the same kind.
6.19.0  the menu turned around: track and race first (TIME TRIAL, Race the
        AI, Race the field or a cup), the car last on its own page with its
        upgrades and the shop; in a cup before every race, so you can change
        cars inside a cup.
6.18.0  Settings has a "Reset all progress" button: back to a fresh install
        (money, points, cars, upgrades, best times, medals, ghosts, opened
        tracks, trophies, trained AI); it asks twice, keeps your settings and
        writes a backup first (trackrush_save.backup.json).
6.17.0  the terminal's "reset everything".
6.16.0  upgrades go to level 10: seven more levels per part, each adding a
        little less and costing a lot more.
6.15.0  the AI you train uses nitro; races against AI cars (Race the AI, Race
        the field, championships) have no nitro for anyone (from 6.31.0
        you have yours again against a single AI).
6.14.0  championships: five cups of three tracks against the same five AI
        drivers, points 10-8-6-5-4-3, trophies and a cup payout.
6.13.0  Race the field: a six-car grid against five named AI drivers, solid
        cars, a podium, pay by place.
6.12.0  sound and music: live engine sounds for every car, tyres, walls, wind,
        race cues, four music tracks, volumes in Settings.
6.11.0  car upgrades: engine, tyres, nitro and loose grip, bought on the car
        page.
The terminal in Settings (or the ` key, under Esc, on the menu) takes commands
such as "money 5000", "car vortex", "upgrade dune max" or "unlock all" (every
car and track); "help" lists them all.

How to run
----------
1. Unzip this folder anywhere (right-click the zip, "Extract All...").
2. Keep these two files together in the same folder:
     TrackRush.exe
     libtrackrush.windows.template_release.x86_64.dll
   The .dll is the fast AI training engine. Without it the game still runs,
   but training the AI is about a hundred times slower.
3. Double-click TrackRush.exe.

Windows may show a blue "Windows protected your PC" (SmartScreen) box the first
time, because the game is not signed with a certificate. Click "More info",
then "Run anyway".

Controls
--------
Arrows or W A S D drive, Space is the handbrake, Shift is nitro, R restarts,
Enter respawns at the last checkpoint, G shows or hides your ghost, Esc goes
back to the menu. On the menu Enter starts a time trial (the car page comes
first: arrows or C pick the car, Enter starts, Esc goes back), T opens the
cups, R the records (top 10s). Press H for every key and gamepad button, and
O for the settings (graphics quality, screen dirt and snow, fullscreen,
vertical sync, interface size, the volumes, the terminal, the reset). The `
key opens the terminal on the menu (not during a race). Any standard gamepad
works.

Where your saves go
-------------------
Best times, ghosts, scores, sector records, top 10s, settings (volumes too), your
money, points, cars, their upgrades and opened tracks, and each car's trained
AI network are kept in

  %APPDATA%\TrackRush\trackrush_save.json

(paste %APPDATA%\TrackRush into the address bar of a File Explorer window).
To start over, press "Reset all progress" in Settings (a backup is written
first, trackrush_save.backup.json in the same folder; to undo the reset, close
the game and rename the backup to trackrush_save.json).
Records set on an older version of a track (the four tracks that got dirt or
snow in 6.3.0, the five with reworked corners in 6.6.0) no longer count there;
the save file keeps them in its "archive" section. Medals and AI wins already
paid stay paid.
Nothing is written next to the game. To uninstall, delete this folder (and
that save folder if you want your records gone too).

Credits
-------
Le Mans is laid out by hand from the real circuit's corners and lengths (no
map data is used). The shapes of Monaco, Silverstone and Spielberg are traced from the circuit
centre lines of bacinger/f1-circuits (github.com/bacinger/f1-circuits):

  MIT License, Copyright (c) 2019-2025 Tomislav Bacinger

  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the "Software"),
  to deal in the Software without restriction, including without limitation
  the rights to use, copy, modify, merge, publish, distribute, sublicense,
  and/or sell copies of the Software, and to permit persons to whom the
  Software is furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
  DEALINGS IN THE SOFTWARE.

More: README.md in the game's repository.
