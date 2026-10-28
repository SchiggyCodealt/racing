# native/: FleetSim, the fast AI training simulation

A small GDExtension (C++, [godot-cpp](https://github.com/godotengine/godot-cpp) tag
`godot-4.5-stable`) with one class, `FleetSim`. It steps a whole AI population in one call:
for every car the sensors, the neural network, the car physics (walls included) and the
training rules (stalled, backwards, too slow, cut off, time, walls "crash" / "ride", the
score and the best times), optionally on several threads. It is a line-by-line port of the
GDScript it replaces, with the same numbers bit for bit:

| C++ | GDScript |
| --- | --- |
| `src/car_sim.cpp` (`car_step`, `walls`, `raycast`, ...) | `sim/car.gd`, `sim/collision.gd` |
| `src/fleet_sim.cpp` (`sense`, `forward`, `drive`) | `ai/sensors.gd`, `ai/network.gd` |
| `src/fleet_sim.cpp` (`step_agent`, `score`, the gates) | `ai/trainer.gd` (`step`, `score`), `sim/race.gd` |

`ai/trainer.gd` uses it whenever it is loaded (`Trainer.native_available()`); without it
(no library for the platform, or one that fails to load) training runs in GDScript, much
slower, and the training screen says so. `tests/test_ai.gd` checks FleetSim against the
GDScript simulation (every car's state and inputs, fitness, reasons, best times) and that
1 and 4 threads give the same results.

Numbers are doubles everywhere the GDScript has floats, and 32-bit floats where the
GDScript (and the browser version) store them: the network's weights and activations, the
sensor inputs, a generation's summed scores. The build turns off fused multiply-adds
(`-ffp-contract=off`), which would round differently.

## Files

- `src/sim_types.h` the car spec, the track, the car state (the fields of `sim/car.gd`)
- `src/car_sim.h/.cpp` the car physics and wall collisions
- `src/fleet_sim.h/.cpp` the `FleetSim` class: the population, the sensors, the network, the rules, threads
- `src/register_types.cpp` the extension's entry point (`trackrush_library_init`)
- `SConstruct`, `build_profile.json` the build (the profile limits godot-cpp to `Object`, `RefCounted`, `OS`)
- `../trackrush.gdextension` names the libraries in `../bin/`

## Building

Needs Python 3 with SCons (4.x), a C++17 compiler, and godot-cpp:

```sh
cd native
git clone --depth 1 -b godot-4.5-stable https://github.com/godotengine/godot-cpp.git godot-cpp
# (or put it anywhere and set GODOT_CPP=/path/to/godot-cpp)
```

Linux (gcc or clang), from `native/`:

```sh
scons platform=linux target=template_debug     # -> ../bin/libtrackrush.linux.template_debug.x86_64.so
scons platform=linux target=template_release   # -> ../bin/libtrackrush.linux.template_release.x86_64.so
```

Windows, cross-compiled on Linux with MinGW-w64 (the posix-threads variant,
`x86_64-w64-mingw32-g++-posix`; Debian / Ubuntu package `g++-mingw-w64-x86-64-posix`):

```sh
scons platform=windows use_mingw=yes target=template_debug     # -> ../bin/libtrackrush.windows.template_debug.x86_64.dll
scons platform=windows use_mingw=yes target=template_release   # -> ../bin/libtrackrush.windows.template_release.x86_64.dll
```

The C++ runtime is linked statically (godot-cpp's `use_static_cpp`, on by default), so the
DLL needs only `KERNEL32.dll` and `msvcrt.dll`
(`x86_64-w64-mingw32-objdump -p <dll> | grep "DLL Name"`). On Windows with Visual Studio,
`scons platform=windows target=template_release` from a developer prompt builds the same DLL
with MSVC (`/fp:precise`; not tried for this release).

Add `-j4` to build on four cores. `out=<dir>` puts the library elsewhere (godot-cpp reports
`out` as an unknown variable: harmless). The editor and debug exports load the
`template_debug` library, release exports the `template_release` one; both are optimised
(godot-cpp's defaults: `-O2` for template_debug, `-O3` for template_release).

Built here with gcc 13.3 (Linux) and MinGW-w64 gcc 13 posix (Windows), godot-cpp
`godot-4.5-stable`, SCons 4.11; run in Godot 4.7.2.

## The class

```gdscript
var fs := ClassDB.instantiate("FleetSim")       # (by name: the game runs without the extension)
fs.set_spec(Trainer.spec_data(Cars.spec("racer")))
fs.set_rules(trainer.rules_data())               # RULES + walls_crash, laps, speed_scale
fs.set_track(Trainer.track_data(track, laps))    # geometry, wall grid, gates, heading tables
fs.set_networks(sizes, population.all_params(), population.size())
fs.set_threads(4)
fs.begin_run()
while not fs.is_run_over():
    fs.step(600, 1.0 / 60.0)                     # returns the steps done (stops at the run's end)
fs.get_fitness(); fs.get_reasons(); fs.get_deaths(); fs.get_best_lap(); fs.get_best_finish()
fs.get_view_states()                             # every car's pose and effect fields (view_stride() each)
fs.get_inputs(k); fs.get_rays(k); fs.get_acts(k); fs.get_car_state(k)
```

`ai/trainer.gd` does all of this; the game never calls FleetSim directly. Threads: the steps
of a call run in chunks of 60, each thread stepping every T-th car; the run's shared numbers
(first finish, best times, deaths) are merged after each chunk. The rules make that
invisible (a car is cut off at least 5 s after the first finish), so every thread count
gives the same results. Below 400 car steps per chunk it stays on one thread.
