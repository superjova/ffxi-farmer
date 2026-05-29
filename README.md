# ffxi-farmer

A gil-per-hour farming HUD for **Final Fantasy XI** on the **Ashita v4** client —
inspired by WoW's gold/XP-per-hour bars.

It shows an always-on, draggable bar with your live **gil/hour**, session total,
elapsed timer, and a count of un-priced drops. It auto-detects the items and gil
you obtain while farming, lets you assign each new item a unit price (remembered
across sessions in a persistent price book), and projects your income rate.

## Features

- **Draggable HUD bar** — drag it anywhere; the position is remembered between
  sessions (saved to Ashita's `config/imgui.ini`).
- **Always-visible stats** — gil/hour, session total gil, raw gil dropped, item
  value, and an elapsed timer.
- **Automatic, solo-focused drop detection** — parses the treasure-pool packet
  (`0x0D2`) to record items and gil as you obtain them.
- **Persistent price book** — once you price an item, future drops of it
  auto-apply the saved price; only never-before-seen items need pricing.
- **Tucked-away pricing** — a collapsible *"N untracked items"* section holds new
  drops until you're ready; expand it to fill in prices.
- **Editable prices** — a *"Tracked items"* section lists priced items with their
  current price, editable inline. Changing a price (or using `/farmer setprice`)
  instantly re-flows into the total and gil/hour.
- **Session controls** — start, pause, reset, and end.

## Install

1. Copy the `addons/ffxi-farmer/` folder into your Ashita installation's `addons`
   directory (e.g. `Ashita/addons/ffxi-farmer/`).
2. In-game (or in your Ashita boot script), load it:

   ```
   /addon load ffxi-farmer
   ```

   To load automatically on every launch, add `/addon load ffxi-farmer` to your
   Ashita script (e.g. `scripts/default.txt`).

## Usage

| Command | Effect |
| --- | --- |
| `/farmer` | Toggle the HUD on/off |
| `/farmer start` | Start (or resume) the session timer & tracking |
| `/farmer pause` | Pause the timer |
| `/farmer end` (or `stop`) | End the session (stops the timer) |
| `/farmer reset` | Reset totals, items, and timer |
| `/farmer price <amount>` | Price the first untracked item (no mouse needed) |
| `/farmer setprice <id\|name> <amount>` | Set/override any item's price |
| `/farmer add <amount>` | Manually add raw gil |
| `/farmer debug` | Toggle raw `0x0D2` packet logging |
| `/farmer help` | List commands |

`/ffxi-farmer` works as a full alias for `/farmer`.

Typical flow: `/farmer start`, go farm. New drops appear under *"N untracked
items"* — expand it and type a unit price for each (it's saved forever). Known
items count automatically. Watch gil/hr climb. `/farmer reset` to start fresh.

## How it works

- **Detection** watches incoming packet `0x0D2` (treasure pool). When an item or
  gil enters the pool, a solo player obtains it, so that's the signal we record.
  Gil arrives as a drop with item id `0` and the gil amount in the gold field.
- **Value is computed on demand** from the price book, so editing any price
  retroactively corrects the whole session's total and gil/hour.
- The first time you farm, run `/farmer debug` once to confirm the packet fields
  (`gold` / `item` / `count` / `slot`) decode correctly on your server; the offsets
  are documented in `addons/ffxi-farmer/tracker.lua` and can be adjusted if a
  private server differs from retail.

## Project layout

```
addons/ffxi-farmer/
  ffxi-farmer.lua  -- header, event wiring, command dispatch
  session.lua      -- session state machine + gil/hr math (pure logic)
  prices.lua       -- persistent price book (pure logic)
  tracker.lua      -- 0x0D2 packet parsing -> session updates
  icons.lua        -- item-id -> cached D3D texture for thumbnails
  item_row.lua     -- reusable ImGui item-row widget (shared by both panels)
  ui.lua           -- ImGui HUD: bar + untracked & tracked panels
  util.lua         -- formatting helpers (commas, HH:MM:SS)
test/run.lua       -- offline unit tests (no client needed)
```

## Development & tests

`session.lua`, `prices.lua`, and `util.lua` are framework-free and unit-tested
with stock Lua (no Ashita client required):

```sh
lua test/run.lua        # run unit tests
luac -p addons/ffxi-farmer/*.lua test/run.lua   # syntax-check
```

The addon targets Ashita v4's LuaJIT (Lua 5.1) runtime.

## Limitations / out of scope (v1)

- Solo-focused: no party loot-competition accounting.
- No auction-house price auto-lookup (prices are entered manually, then saved).
- No multi-session history/graphs.
- Tracks gil only (no XP/hour).
