# EqManager

EqManager is a robust equipment set management addon for World of Warcraft, designed to handle complex gear swapping needs with ease. It allows users to save, manage, and automatically trigger equipment changes based on a wide variety of in-game events.

EqManager is inspired by the **GearQuipper** addon. While it draws inspiration from GearQuipper's robust equipment management, EqManager is a **complete cleanroom rewrite** designed with a more modular and strictly demarcated architecture. Notably, EqManager **does not include action bar management**, focusing purely on equipment excellence.

## Features

### Set Management
- **Full & Partial Sets**: Save complete equipment sets or subset elements for specific needs.
- **Reconstruction System**: Intelligent tracking of a Base Set and multiple Active Partial Sets, automatically handling un-equips to maintain your desired appearance and stats.
- **Base Set Protection**: Ensures fundamental gear states are maintained by preventing base sets from being unequipped.
- **Base Set Re-equip**: Click the base set label or checkbox to clear all partials and reset to your base gear configuration.
- **Auto-Detect Notifications**: Chat messages alert you when a partial set is detected as equipped or unequipped.
- **Custom Sorting**: Reorder your equipment sets manually using dedicated Up/Down buttons in the main UI.
- **Per-Character Settings**: Each character maintains its own independent configuration, including auto-update preferences and UI options.
- **GearQuipper Import**: Seamlessly migrate all your sets, partial slots, and event bindings from GearQuipper with a single click.


### Equipment Queue & State Machine
- **Safety First**: Queues equipment changes during combat, casting, or shapeshifting, executing them safely as soon as the lockdown ends.
- **Conflict Resolution**: Handles race conditions by cancelling redundant or conflicting requests in rapid succession.
- **Latency Aware**: Adjustable switch delays to account for home/world latency, preventing server rate-limiting.
- **Delayed Resumption**: Adds a safety buffer after casting or combat ends before resuming swaps, ensuring stability during rapid actions like smelting.
- **Robust Verification**: Automatically verifies equipment states after a swap, with up to 3 automatic retries if items fail to equip/unequip.


### Automated Event Engine
Trigger automatic set swaps based on:
- **Zone Transitions**: Entering or leaving specific zones, Battlegrounds, or Arenas.
- **Player States**: Mounting/Dismounting, entering Stealth, or going AFK.
- **Environment States**: Trigger swaps when Submerging or Emerging from water.
- **Group Dynamics**: Automatically switch gear when joining or leaving a Party or Raid.
- **Class Mechanics**: Druid Forms, Paladin Auras, Death Knight Presences, and Warrior Stances.
- **Talent Specialization**: Automatic swaps when switching dual-specs with human-readable "Primary" and "Secondary" labels.
- **Expanded Zone Support**: Recursive scanning of multiple continents (Azeroth, Outland, Northrend, etc.) for comprehensive zone-based triggers.
- **PVP Status**: Conditional switches based on PVP combat status.
- **Conditional Filtering**: Specify conditions like PvP status or Location (Outland vs. Azeroth) for each individual event action.

### User Interface & Integration
- **Character Frame Integration**: Seamlessly adds a "SETS" button and labels to the standard PaperDollFrame.
- **Quick Slots**: Alt/Shift-click popups on equipment slots for lightning-fast manual swaps.
- **Visual Feedback**: Highlights missing items (red) and equipped items (green) with clear visual cues.
- **Missing Item Highlighting**: Set names in the list turn red if items are missing from your bags, with a detailed tooltip listing the missing pieces.
- **Bag Dimming**: Dims items in your bags that aren't part of any saved set (Supports Baganator).
- **Item Set Tooltips**: Displays set membership information directly on item tooltips with support for partial set indicators and membership status.
- **Event Provenance**: Detailed chat logging that identifies the specific event or manual action that triggered an equipment change.
- **Intelligent Selection**: Clicking a set name automatically selects it for editing and ensures it is equipped so you can immediately configure its slots.
- **Detailed Set Feedback**: Chat messages list exactly which items were updated during a manual save or automatic gear update.
- **Searchable Zone Picker**: A dedicated, searchable, and scrollable picker UI for easily finding zones among hundreds of options.
- **Refined Event Configuration**: Set PvP and Location conditions directly when adding or editing actions for an event.
- **Responsive UI**: Automatically detects and repositions its panes if other UI addons (like Extended Character Stats) are present.


### Compatibility
- Specifically tailored and tested for **Burning Crusade (TBC) Classic**.
