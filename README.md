# Tower of Food 🍔🍕🍩

A food-themed **Tower of Hell**. The whole game is one giant tower. You start in the lobby at the bottom, then climb a random stack of food obbies before the timer runs out. There are no checkpoints, and a fresh tower comes out of the oven every 6–8 minutes.

## What's in it

- **16 food sections**, 8 per tower, getting harder as you climb: Nugget Steps, Ketchup Slide, Spinning Pizza, Hot Sauce Lava, Jelly Bounce, Noodle Swing, Burger Stack, Ice Cream Melt, Popcorn Pop, Spaghetti Sweeper, Donut Drift, Sushi Conveyor, Waffle Wall, Cheese Maze, Chocolate River, Cake Tiers
- **Tower of Hell-style screen**:
  - big timer at the top
  - progress bar on the right with everyone's avatar
  - Menu and coins at the bottom left
  - level, XP bar and skill points at the bottom centre
  - music player at the bottom right
- **Coins:** 12.5 per section + 100 for reaching the top
- **Levels and skill points:** spend points on Quick Feet, Springy Legs, Coin Chef and Fast Learner
- **Shop:**
  - Speed, Gravity and Fusion coils
  - Ketchup, Mustard, Rainbow, Sprinkle and Golden Fry trails
- **Round bonuses** (40% of rounds): x2 coins, low gravity, speedy or bouncy
- **Gamepasses, ready to switch on:** x2 Coins, Double Jump, Skip Section, VIP and Nugget Trail
- **Codes:** `FOOD` and `NUGGET`
- **Top Wins board** in the lobby, and everything saves

## Install (the easy way, about 1 minute)

1. Open your **Tower of Food** place in Roblox Studio. An empty Baseplate is fine; the script removes the baseplate itself.
2. Turn on the Command Bar: **View** tab > **Command Bar**. A long box appears at the bottom of the screen.
3. Copy the whole line from [`install/command-bar.lua`](install/command-bar.lua). Open it, then click the **Copy raw file** button (two squares, top right).
4. Click in the Command Bar, paste, and press **Enter**.
5. The Output window should say `Tower of Food installed!`.
6. Press **Play**.

To **update** later, do steps 3–4 again. It replaces the old scripts with the newest version.

> The installer turns on *Allow HTTP Requests* so Studio can download the scripts from GitHub.
> If you see `HTTP requests are not enabled`, go to **Home > Game Settings > Security**, turn on **Allow HTTP Requests**, and try again.

## Install (the manual way)

If the Command Bar way doesn't work, paste these 4 scripts by hand. For each one:
1. Hover over the place in the **Explorer** and click **+**.
2. Choose the type shown and rename it exactly.
3. Open the GitHub file, click **Copy raw file**, and paste it into the script.

| Put it in | Type | Name | File |
|---|---|---|---|
| ServerScriptService | ModuleScript | `TowerSections` | [TowerSections.lua](src/ServerScriptService/TowerSections.lua) |
| ServerScriptService | Script | `TowerGame` | [TowerGame.server.lua](src/ServerScriptService/TowerGame.server.lua) |
| StarterPlayer > StarterPlayerScripts | LocalScript | `TowerHUD` | [TowerHUD.client.lua](src/StarterPlayer/StarterPlayerScripts/TowerHUD.client.lua) |
| StarterPlayer > StarterPlayerScripts | LocalScript | `TowerObstacles` | [TowerObstacles.client.lua](src/StarterPlayer/StarterPlayerScripts/TowerObstacles.client.lua) |

If you still have the old `TowerClient` LocalScript from version 1, delete it.

## Turn on saving

1. **File > Publish to Roblox**.
2. **Home > Game Settings > Security** > turn on **Enable Studio Access to API Services** > **Save**.

## Put it live

**File > Publish to Roblox**. Then, on the game's Roblox page, click **⋯ > Shut Down All Servers** so everyone gets the new version.

## Changing things (top of the `TowerGame` script)

- `CONFIG`: number of sections, round time, coins, XP, round-bonus chance
- `CONFIG.PASSES`: paste your gamepass IDs here once you make them. Go to **Creator Hub > your game > Monetization > Passes**. Passes with ID `0` show "Coming soon".
- `CONFIG.MUSIC`: add songs from the Toolbox (**Audio** tab, right-click a song > **Copy Asset ID**)
- `CONFIG.CODES`: add your own codes
- `SHOP_ITEMS`: prices for coils and trails

## For developers

- `docs/ARCHITECTURE.md`: how the 4 scripts fit together
- `tools/check.sh`: strict type check against the Roblox API, plus the section test harness
