# fishingtracker-twow

Lightweight Turtle WoW fishing helper addon with a lure panel + fish catch tracker.

<img width="370" height="441" alt="image" src="https://github.com/user-attachments/assets/8474bec5-843e-4976-989b-a5e60cda4429" />


## Features

- Shows a compact **Lure panel** when a fishing pole is equipped.
- Detects whether a lure is active and shows a **remaining timer**.
- One-click **Apply Lure** button:
  - Finds the best known lure in your bags.
  - Applies it to your fishing pole automatically.
- Tracks fish loot from chat and displays totals in a **Fish Meter** panel.
- Multiple stat views:
  - **Session**
  - **Last 7 Days**
  - **Overall**
- **Reset button** clears session totals only.
- Remembers panel position between sessions.
- Daily history is automatically pruned to keep only the latest 7-day window.

## Known lures supported

- Shiny Bauble (+25)
- Nightcrawlers (+50)
- Bright Baubles (+75)
- Aquadynamic Fish Attractor (+100)
- Flesh Eating Worm (+100)
- Sharpened Fish Hook (+100)

## Usage

1. Equip a fishing pole.
2. The addon panels appear automatically.
3. Click **Apply Lure** to use the best lure found in your bags.
4. Hold **Shift** and drag the lure panel to move it.
5. Use the fish tracker dropdown to switch between Session / Last 7 Days / Overall.

## Installation

1. Download or clone this repo.
2. Place the addon folder in your WoW AddOns directory:
   - `Interface/AddOns/fishingtracker-twow`
3. Ensure the folder contains:
   - `fishingtracker-twow.toc`
   - `fishingtracker-twow.lua`
4. Restart WoW or `/reload`.

## Notes

- Saved variables use `TatoFishingDB` for backward compatibility with older versions.
- Fish tracking currently uses a curated item ID list and can be extended easily.

## Version

Current addon metadata version: `2.0.0`
