Track Rush 6.18.0 for Windows (64-bit)
======================================

A Trackmania-style racer with six cars, fifteen tracks (seven of them with dirt
or packed snow), medals, ghosts and an AI driver you train yourself, with any
of the cars. Medals and wins against five AI opponents (Rookie to Elite) pay
money and career points, and money buys cars and upgrades. The tracks open one
at a time: you start with Rookie Oval, and a bronze medal or better on a
track, with any car, opens the next one for good.

New in 6.18.0: Settings has a "Reset all progress" button. It puts the game
back to a fresh install (money, points, cars, upgrades, best times, medals,
ghosts, opened tracks, trophies and your trained AI networks) and keeps your
settings. It asks twice, and it first writes a backup of the save next to it
(trackrush_save.backup.json). In the terminal, "reset everything" does the
same: it asks first, and a plain "yes" answers it.

Earlier versions, newest first:
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
        picker.
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
back to the menu. On the menu press H for every key and gamepad button, and
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
