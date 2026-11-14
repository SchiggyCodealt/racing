Track Rush 6.23.0 for Windows (64-bit)
======================================

A Trackmania-style racer with seven cars, nineteen tracks (seven of them with
dirt or packed snow, four of them rally stages on gravel, sand, ice and mud),
medals, ghosts and an AI driver you train yourself, with any of the cars.
Medals and wins against five AI opponents (Rookie to Elite) pay money and
career points, and money buys cars and upgrades. The tracks open one at a
time: you start with Rookie Oval, and a bronze medal or better on a track,
with any car, opens the next one for good.

New in 6.23.0: four rally stages, tracks 16 to 19. Point-to-point sprints of
3.2 to 3.9 km, each on a new road surface with its own texture and scenery:
Pine Ridge (gravel through a pine forest), Dune Sea (soft sand over desert
dunes), Frozen Lake (bare ice and packed snow) and Monsoon Trail (deep mud in
the jungle). Sand and mud drag the car down, ice gives a quarter to a half of
the grip and hardly slows the car at all. The Dune is the car for all four.
A sixth championship, the Rally Cup, runs the four stages back to back. The
stages come after Summit Rush: if you already have a bronze there, Pine Ridge
is open when you start the game. Also fixed: braking on dirt or snow just as
the front wheels went light over a crest could break the car.

Earlier versions, newest first:
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
        the field, championships) have no nitro for anyone.
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
cups. Press H for every key and gamepad button, and
O for the settings (graphics quality, screen dirt and snow, fullscreen,
vertical sync, interface size, the volumes, the terminal, the reset). The `
key opens the terminal on the menu (not during a race). Any standard gamepad
works.

Where your saves go
-------------------
Best times, ghosts, scores, settings (volumes too), your money, points, cars,
their upgrades and opened tracks, and each car's trained AI network are kept in

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

More: README.md in the game's repository.
