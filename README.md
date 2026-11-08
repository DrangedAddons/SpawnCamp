# SpawnCamp

WoW Forever addon for camping a mob: one key to tag it, one key to talk to it (chat, quest hand-ins and accepts), and a respawn timer built from the kills it has seen.

## The window

A small window stays on screen:

```
[icon] SpawnCamp                  [+] [Nearby] [gear] [x]
Attack: F (Moonfire)    Talk: G
Mob name     status / countdown        [sword] [bubble]
```

1. **Add a mob.** Target it and press **+**, or pick it from **Nearby**. If the game hides the name (it does in dungeons), **+** opens a box: type the name exactly as your target frame shows it.
2. **Pick sword or bubble** on its line.
   - **Sword**: your **Attack** key goes for this mob.
   - **Bubble**: your **Talk** key talks to it. Chat is clicked through, finished quests are handed in, and new and follow-up quests are accepted.
   - Neither: timer only. Click a lit icon again to turn it off.
3. **Set your two keys once**, in the gear settings. The first time you light a sword or bubble without a key, the settings open.

Click a mob's name for its details: status, respawn times, full history, alarms, and the manual **It died now** / **It's up now** buttons. Drag the window by its header.

The game requires a real keypress for every target, cast and interact. SpawnCamp doesn't press anything for you and never will.

## Settings (gear)

**Attack**
- **Key**: one key for every sword mob. It runs:
  ```
  /cleartarget
  /targetexact First Mob
  /targetexact [noexists] Second Mob
  /cast [@target,harm,nodead] <spell>
  /startattack [@target,harm,nodead]
  ```
  When no mob is there you end up with no target, so it never casts on anything else.
- **Spell**: drag an instant spell from your spellbook. Empty = auto attack only.
- **Custom macro** (optional): replaces the spell part. `{target}` becomes the targeting lines.

**Talk**
- **Key**: one key for every bubble mob.
- **Reach**:
  - **Target by name** (default)
  - **Mouseover**: the NPC under your mouse
  - **Nearest**: the game's Interact key. With soft interact on (there's a button for it) it also reaches chests and quest items.
- **Hand in and accept quests** and **Click through chat**: both on by default. With several chat options it picks one matching your **Prefer** list, or asks you.
- **Reward choice**: for quests with several rewards. Empty = you pick.
- Hold **Shift** while talking to do a window yourself.

**General**: share sightings with group/guild, sound, keep mobs you already got on the list, lock the window.

Each key only takes over while at least one mob uses it. Untick all swords and your Attack key goes back to its normal binding.

## Respawn timer

SpawnCamp logs a **death** when it sees a watched mob dead and a **spawn** when it sees one alive. It reads nameplates, your target and your mouseover, plus what your keys target. Each death followed by a spawn gives a respawn time. The details show the earliest, average and latest, and the line's bar counts down to the earliest.

- **Respawn alarm** goes off a set time before the earliest respawn, and again when the window opens.
- **Alert when it spawns** goes off when it's seen alive (by you, or by another SpawnCamp user with sharing on).
- **Known respawn** (minutes) overrides the history.
- When you get the kill yourself, the mob comes off the Attack key and is marked "got".

### Hidden names (dungeons)

In dungeons Forever hides NPC names from addons. SpawnCamp then knows a mob by your key: a target right after an Attack or Talk press is that key's mob. If the key covers several mobs, it can only tell which one when the name is readable. A chat or quest window within 8 seconds of a Talk press gets handled.

## Commands

- `/spawncamp` (or `/spc`): show or hide the window
- `/spawncamp settings`: open the settings
- `/spawncamp add [name]`: watch your target, or a mob by name
- `/spawncamp died [name]` / `up [name]`: log a sighting now
- `/spawncamp probe`: print and save what the addon can read (for bug reports)
