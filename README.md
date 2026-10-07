# Tower of Food 🍔🍕

A Tower of Hell-style Roblox obby made of food. Every 6–8 minutes, a new random 8-stage tower gets built.

## What's in the game

- **9 food sections**, 8 picked at random each round: Nugget Steps, Ketchup Slide (slippery), Spinning Pizza, Hot Sauce Lava (tiles turn deadly), Jelly Bounce (trampolines), Noodle Tightrope, Burger Stack, Ice Cream Melt (melts when you touch it), Popcorn Pop (kernels vanish)
- No checkpoints. If you fall, you drop back down. When the timer hits 0, everyone goes back to the lobby and a new tower is built.
- **Coins:** 12.5 per stage + 100 for reaching the top = 200 for a full climb
- **XP & levels:** 10 XP per stage, 100 XP per win. Your level shows on the leaderboard and above your head.
- **Shop:** Speed Coil (250), Gravity Coil (400), Fusion Coil (1000), saved forever with DataStore

## Install it in Roblox Studio (about 5 minutes)

You only paste **2 scripts**. They build everything else themselves.

### Script 1: the game (server)

1. Open your **Tower of Food** place in Roblox Studio.
2. In the **Explorer** panel, hover over **ServerScriptService**, click the **+** and choose **Script**.
3. Rename it to `TowerGame` (right-click > Rename).
4. Open [`src/ServerScriptService/TowerGame.server.lua`](src/ServerScriptService/TowerGame.server.lua) on GitHub and click the **Copy raw file** button (two overlapping squares, top-right of the code).
5. Double-click the script in Studio, delete the `print("Hello world!")` line, and paste (Ctrl+V).

### Script 2: the screen UI (client)

1. In **Explorer**, expand **StarterPlayer**, hover over **StarterPlayerScripts**, click **+** and choose **LocalScript**.
2. Rename it to `TowerClient`.
3. Copy [`src/StarterPlayer/StarterPlayerScripts/TowerClient.client.lua`](src/StarterPlayer/StarterPlayerScripts/TowerClient.client.lua) the same way and paste it in.

### Turn on saving

1. **File > Publish to Roblox** (if you haven't already).
2. **Home > Game Settings > Security** and turn on **Enable Studio Access to API Services**. Click **Save**.

### Test it

Press **Play**. You'll spawn in the lobby facing the glass tower. Walk through the door and start climbing!

> Note: the script deletes the default `SpawnLocation` and makes its own lobby spawn. That's expected.

### Put it live

Use **File > Publish to Roblox** after every change. Then go to the game's page on Roblox and use **⋯ > Shut Down All Servers** so players get the new version.

## Changing things

All the easy settings are at the top of `TowerGame`, in `CONFIG` and `SHOP_ITEMS`: number of stages, round time, coin amounts, shop prices, and the gamepass ID for x2 coins.

## Planned next

Gamepasses: x2 coins (already wired in, just needs an ID), double jump, skip section, VIP, nugget trail.
