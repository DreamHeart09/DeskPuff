# DeskPuff Player Guide

[简体中文](PLAYER-GUIDE.md) · [Game homepage](../README.md) · [Gameplay showcase](../README.md#features)

[First session](#first-session) · [Controls](#controls) · [Desktop physics experiments](#desktop-physics-experiments) · [Recovery and crafting](#recovery-and-crafting) · [Collection, customization, and progression](#collection-customization-and-progression) · [Settings and FAQ](#settings-and-faq)

## First session

### Find DeskPuff in the menu bar

After [building and launching DeskPuff](../README.md#get-started), click its icon in the macOS menu bar. Under **Desktop Objects**, set **Desktop** to **Show** and start with **Free Placement**. You can hide the scene from the same panel. Your progress is stored on this Mac, and you can start playing without an account.

### Take a cigarette out of the pack

1. Click the body of the pack. Wait for the lid to open and reveal the cigarettes.
2. Drag a cigarette out. Grab the middle to move it or grab near either end to rotate it.
3. Double-click the body of the lighter to ignite it. Move the flame to the cigarette tip and wait for the tip to glow. Move the lighter away and double-click it again to turn it off.
4. Hold the lit cigarette for a moment, then release to take a puff. Once ash has built up at the tip, double-click the cigarette to tap it off.
5. Right-click the cigarette and choose **Stub Out**, or put the burning end into an ashtray.

Next, [try a physics experiment](#desktop-physics-experiments) or [take the bag out to catch some ash](#recovery-and-crafting).

## Controls

| To do this | Use this control |
| --- | --- |
| Open or close the pack | Click the body. Drag a cigarette out once the pack is open. |
| Move or rotate the pack | Drag the body to move it or the lower-right handle to rotate it. |
| Return a cigarette to the pack | Line up an unused, undamaged cigarette with the open pack and drag it into a free slot. |
| Move or rotate a cigarette | Drag the middle to move it. Drag near either end to rotate it. |
| Toggle the lighter flame | Double-click the body of the lighter away from the flame adjustment area. |
| Take a puff or knock off ash | Hold and release the lit cigarette to puff. Double-click once ash has built up to knock it off. |
| Extinguish a cigarette | Right-click and choose **Stub Out**, or place the burning end into an ashtray. |
| Turn on gravity | Menu bar → **Motion** → **Gravity**. Choose **Free Placement** to arrange objects by hand. |
| Clear the view | Menu bar → **Desktop** → **Hide**. Use the item's context menu or the bag to put away individual objects. |
| Bring out the desktop bag | Right-click the DeskPuff menu bar icon and choose **Place Bag on Desktop**. |

## Desktop physics experiments

### Catch ash on a window

Open a regular Finder window and move it toward the middle of the screen. Position a cigarette with ash at its tip above the top edge. Double-click and watch for fragments that settle on the ledge. Try again beside the window. Start in **Free Placement** so you can change the drop point while keeping the rest of the setup similar.

### Disturb a plume

Light a cigarette and let the plume rise while it sits still. Grab the middle, drag it sideways, and watch the old trail and fresh smoke. A plain background makes both easier to see. If the plume fades too quickly, adjust **Fade** in the menu bar.

### Drop and collide

Set **Motion** to **Gravity**, lift the cigarette above the bottom of the screen, and let go. Repeat from the same height after rotating it slightly and watch where it hits. To look for creases, try an angled impact against a screen edge and inspect the contact area after it stops.

[Back to the gameplay showcase](../README.md#features)

## Recovery and crafting

### Collect ash in the bag

1. Right-click the menu bar icon and choose **Place Bag on Desktop**.
2. Put the opening in the path of falling ash, or move it across ash on the desktop.
3. Watch for the pickup confirmation. You can also drag a butt into the opening when its context menu shows that it can be recycled. If the bag is full, free some grid space first.

### Craft something

1. Open **Bag** from the menu bar to reach the player hub, then switch to **Recycling** and open the **Freeform Crafting Workshop**.
2. Select two materials you own and start with one unit of each. The preview shows the expected item, how many you'll get, and any extra materials that will be used up.
3. Confirm when you're happy with the preview, then check the collection for your first discovery. If the preview says **A Lump of Ash**, you can try a different combination or craft it anyway.
4. Keep or sell what you made. Once something is discovered, its collection entry stays unlocked after sale.

Packs count as different materials by style. Using a partially full pack also consumes the cigarettes left inside. Start exploring recipes with the in-game preview and materials from play.

## Collection, customization, and progression

| Open | What you can find there |
| --- | --- |
| **Stats** | Rank, stars, progress, and income records. Using cigarettes advances your rank, which determines your periodic allowance. |
| **Bag** | Desktop objects, materials, and collectibles. Place or store objects and make room for crafting and purchases. |
| **Shop** | Supplies, desktop objects, and styles. Check your balance and available bag space when purchasing. |
| **Recycling** | Experiment with recipes, inspect your collection, and sell items you want to clear out. |

[Custom style packs](style-packs/README.md)

## Settings and FAQ

- **My desktop objects are missing.** Set **Desktop** to **Show** in the menu bar, then check the **Bag** for objects you still need to place.
- **The cigarette won't light.** Check that the lighter is on and its flame reaches the tip. Double-click the body of the lighter away from the flame adjustment area.
- **There's too much smoke, or I want it behind windows.** Adjust **Fade** and **Smoke Layer** in the menu bar. In game settings, you can reduce the amount of smoke or turn on **Power Saving**. Smoke amount and rendering quality are separate settings.
- **macOS shows a warning when I open a local build.** Local builds use ad-hoc signing. For an app built from a source you trust, follow the options offered by your version of macOS. See [Build and packaging (Chinese)](BUILD-AND-PACKAGING.md).
- **The widget isn't in the gallery.** The small and medium widgets show rank, balance, and progress. First check that the build embedded the widget extension, then launch DeskPuff and check the gallery. Gallery visibility and the shared snapshot still need verification on the target Mac.
- **Where is my save?** Game state and settings are stored on this Mac. Quitting or removing the app may leave that data in place. Account-based cloud sync is currently unavailable.
