# SpawnCamp

WoW Forever addon for camping a mob: one key to tag it or talk to it (chat, quest hand-ins and accepts), and a respawn timer built from the kills it has seen.

## The window

A small window stays on screen. Each watched mob gets a line:

```
[ type or paste a mob name ] [Add] [Current Target] [Nearby]
(portrait)  Mechanized Sentry            [Attack] [Talk]
            dead 2:05, due in 2:55
```

- **Add a mob** in one of three ways:
  - Type or paste its name and press **Add** (or Enter).
  - Press **Current Target**.
  - Open **Nearby** and press **Add** next to a mob.

  Hostile mobs start on Attack, friendly ones on Talk. Where the game hides the name (dungeons), type it exactly as your target frame shows it.
- **Attack / Talk**: one of the two is always pressed, and it says what your key does to that mob. Clicking the pressed one does nothing; clicking the other swaps them.
  - **Attack**: targets it, casts your attack spell, starts auto attack.
  - **Talk**: targets it and talks to it. Chat is clicked through, finished quests are handed in, and new and follow-up quests are accepted.
- **Portrait**: grabbed whenever the mob is your target or on a nameplate. A question mark until then.
- **Click a mob's name** for its details: respawn times, full history, alarms, manual "it died / it's up" buttons.

## One key

Set one **SpawnCamp key** in the settings (gear, or click the key line under the title). It covers every mob you are still hunting:

```
/cleartarget
/targetexact Sword Mob
/targetexact [noexists] Other Sword Mob
/targetexact [noexists] Bubble NPC
/cast [@target,harm,nodead] <spell>
/startattack [@target,harm,nodead]
/click [help,nodead] SpawnCampInteract
```

A hostile target gets the attack lines and a friendly one gets talked to. If no mob is there you end up with no target, so nothing lands on anything else. The key only takes over while at least one mob is on it.

The game requires a real keypress for every target, cast and interact. SpawnCamp doesn't press anything for you and never will.

## Settings (gear)

- **Key**: the one SpawnCamp key.
- **Attack**:
  - **Spell**: drag an instant spell from your spellbook. Empty = auto attack only.
  - **Custom attack lines**: optional, replace the spell lines.
- **Talk**:
  - **Hand in and accept quests** and **Click through chat**: both on by default. With several chat options it picks one matching your **Prefer** list, otherwise the first one.
  - **Quest reward**: which reward to take when a quest offers a choice. 1 (the default) = first, 2 = second, and so on. Empty = you pick.
  - Hold **Shift** while talking to do a window yourself.
- **General**:
  - Share sightings with **Party**, **Raid** and **Guild**: separate boxes.
  - **Show mobs I've already killed**: when you get the kill on a mob, it comes off your key and is marked "got". Ticked, it stays on the list; unticked, it's hidden.
  - Sound with alerts, lock window.

## Respawn timer

The timer starts when the mob dies and stops when it's seen alive again. That time is the respawn. The line shows `dead 2:05` while it's down (with `due in` once there's history), then `UP, respawned after 4:51`. SpawnCamp sees deaths and spawns on nameplates, your target, your mouseover, and whatever your key targets. The details show the earliest, average and latest respawn.

- **Respawn alarm** goes off a set time before the earliest respawn, and again when the window opens.
- **Alert when it spawns** goes off when it's seen alive (by you, or by another SpawnCamp user in a party, raid or guild you share with).
- **Known respawn** (minutes) overrides the history.
- When you get the kill yourself, the mob comes off your key and is marked "got". Tick **Still hunting** in its details to put it back.

### Hidden names (dungeons)

In dungeons Forever hides NPC names from addons. SpawnCamp then knows a mob by your key: a target right after a press is one of your lit mobs. Hostile means an Attack mob, friendly a Talk mob. If several mobs share that side, it can only tell which one when the name is readable. A chat or quest window within 8 seconds of a press that targeted a friendly NPC gets handled.

## Commands

- `/spawncamp` (or `/spc`): show or hide the window
- `/spawncamp settings`: open the settings
- `/spawncamp add [name]`: watch your target, or a mob by name
- `/spawncamp died [name]` / `up [name]`: log a sighting now
- `/spawncamp probe`: print and save what the addon can read (for bug reports)
