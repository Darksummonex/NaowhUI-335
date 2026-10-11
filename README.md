# NaowhUI for WoW 3.3.5a

A 3.3.5a (Wrath of the Lich King, build 12340) port of **NaowhUI**, Naowh's profile
installer, built as a plugin for the
[EllesmereUI 3.3.5a backport](https://github.com/Darksummonex/EUI-port).

> **All credit for NaowhUI goes to [Naowh](https://github.com/naowh-gaming) and NWH Gaming AB.**
> The original addons, profiles, art, sounds and design are theirs, with all rights reserved.
> This repository only adapts them to run on the 3.3.5a client. See [LICENSE.md](LICENSE.md).
>
> - NaowhUI: <https://github.com/naowh-gaming/NaowhUI>
> - NaowhUI_EUI: <https://github.com/nwh-gaming-ab/NaowhUI_EUI>

## What it does

- `/nui install` runs the NaowhUI installer and applies Naowh's EllesmereUI profile.
- Imports the class WeakAuras (Merfin's WotLK class auras, 1080p or 1440p, all 10 classes)
  re-anchored to EllesmereUI unit frames, plus the general NaowhUI WeakAuras.
- NaowhUI_EUI adds the Naowh skin, top bar, icons, nameplate and cooldown styling, and QoL
  helpers on top of EllesmereUI.

## Requirements

- WoW 3.3.5a client.
- [EllesmereUI 3.3.5a](https://github.com/Darksummonex/EUI-port/releases) (Core and Options at least).
- WeakAuras for 3.3.5a (optional, needed for the WeakAuras step).
- The four NaowhUI fonts from the official NaowhUI_Media (not included, see below).

## Installation

1. Copy `NaowhUI`, `NaowhUI_Data`, `NaowhUI_EUI` and `NaowhUI_Media` into
   `World of Warcraft\Interface\AddOns`.
2. Copy `GothamNarrowUltra.ttf`, `GothamNarrowUltraAsia.ttf`, `Naowh.ttf` and `NaowhAsia.ttf`
   from the official NaowhUI_Media into `NaowhUI_Media\Shared\Fonts`. Their licenses don't
   allow them to be redistributed here.
3. Restart the game and type `/nui install`.

## Credits

- **Naowh** and **NWH Gaming AB**: NaowhUI, NaowhUI_EUI, profiles, media and design.
- **Merfin**: the WotLK class WeakAuras.
- **Ellesmere**: EllesmereUI.
- **Laraystiri**: the 3.3.5a port.

Not affiliated with or endorsed by Naowh, NWH Gaming AB, Merfin or Blizzard Entertainment.
