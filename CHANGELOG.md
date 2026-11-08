# Changelog

## 0.2.2

- Unit names come from the first source that gives a readable name: UnitName, GetUnitName, UnitNameUnmodified, the unit's tooltip data, then the game tooltip (mouseover). Forever can hide UnitName.
- A unit whose existence the game hides is still checked by name.
- **+** (watch my target) now says why it failed: no target, a player, or a name it can't read.
- `/spawncamp probe` prints every read for target, mouseover and the first nameplate, and saves it to SpawnCampDB.probe.
- Button errors are printed in chat.

## 0.2.1

- Nearby: a **Scan now** button reads all nameplates, your target and your mouseover immediately. A line at the bottom says how many NPCs it read and how many it skipped or couldn't read (players, pets, names the game hides, errors). Opening the list scans too.
- Nameplates 1-40 are read directly every tick, so the list and the spawn tracker no longer depend on nameplate events.
- Unit checks accept the 1/nil style of return as well as true/false. Before, a client returning 1 made every unit look like it didn't exist.
- `/spawncamp debug` also prints the first nameplate's reads and a nearby scan report.

## 0.2.0

- One compact window replaces the big window and the timer list. It stays on screen with a line per mob (status, countdown bar, key). **More** opens Setup, History and Options tabs under it.
- Setup is laid out in steps: 1. Action, 2. What it does, 3. Key, 4. Alarms.
- New action: **Custom macro**. Your own macro text runs on the key, with `{mob}` replaced by the name. It can start from the attack macro.
- **Nearby** list: NPCs seen on nameplates, as target or as mouseover in the last 3 minutes, rares first. Click one to watch it.
- **+** in the header watches your target and opens its setup.

## 0.1.0

- First version.
- Attack mode: one key targets the watched mob by exact name and casts your chosen instant spell, then starts auto attack. A miss leaves you with no target.
- Interact mode: target by name, mouseover, or the game's Interact key (with a button to turn on soft-target interact for objects).
- Watched NPCs: finished quests are handed in, available and follow-up quests accepted, and chat options picked from your list. Hold Shift to skip.
- Respawn tracking from nameplates, target and mouseover: death and spawn history per realm, earliest/average/latest respawn, timer list, alarm before the earliest respawn, spawn alert.
- Sightings are shared with party/raid and guild members running SpawnCamp.
- Your own kill stops hunting that mob and frees its key.
