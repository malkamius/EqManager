# EqManager

EqManager is a robust equipment set management addon for World of Warcraft, designed to handle complex gear swapping needs with ease. It allows users to save, manage, and automatically trigger equipment changes based on a wide variety of in-game events.

EqManager is inspired by the **GearQuipper** addon. While it draws inspiration from GearQuipper's robust equipment management, EqManager is a **complete cleanroom rewrite** designed with a more modular and strictly demarcated architecture. Notably, EqManager **does not include action bar management**, focusing purely on equipment excellence.

## Features

### Set Management
- **Full & Partial Sets**: Save complete equipment sets or subset elements for specific needs.
- **Reconstruction System**: Intelligent tracking of a Base Set and multiple Active Partial Sets, automatically handling un-equips to maintain your desired appearance and stats.

### Equipment Queue & State Machine
- **Safety First**: Queues equipment changes during combat, casting, or shapeshifting, executing them safely as soon as the lockdown ends.
- **Conflict Resolution**: Handles race conditions by cancelling redundant or conflicting requests in rapid succession.
- **Latency Aware**: Adjustable switch delays to account for home/world latency, preventing server rate-limiting.

### Automated Event Engine
Trigger automatic set swaps based on:
- **Zone Transitions**: Entering or leaving specific zones, Battlegrounds, or Arenas.
- **Player States**: Mounting/Dismounting, entering Stealth, or going AFK.
- **Class Mechanics**: Druid Forms, Paladin Auras, Death Knight Presences, and Warrior Stances.
- **Talent Specialization**: Automatic swaps when switching dual-specs.
- **PVP Status**: Conditional switches based on PVP combat status.

### User Interface & Integration
- **Character Frame Integration**: Seamlessly adds a "SETS" button and labels to the standard PaperDollFrame.
- **Quick Slots**: Alt/Shift-click popups on equipment slots for lightning-fast manual swaps.
- **Visual Feedback**: Highlights missing items (red) and equipped items (green) with clear visual cues.
- **Bag Dimming**: Dims items in your bags that aren't part of any saved set (Supports Baganator).
- **Item Set Tooltips**: Displays set membership information directly on item tooltips with support for partial set indicators and membership status.
- **Responsive UI**: Automatically detects and repositions its panes if other UI addons (like Extended Character Stats) are present.

### Compatibility
- Specifically tailored and tested for **Burning Crusade (TBC) Classic**.
