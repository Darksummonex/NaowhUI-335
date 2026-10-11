# License

This repository mixes code owned by different people. Each part keeps its own license.

## 1. NaowhUI (original work): all rights reserved

NaowhUI, NaowhUI_Data, NaowhUI_EUI and NaowhUI_Media are the work of **Naowh** and
**NWH Gaming AB**:

- NaowhUI / NaowhUI_Data / NaowhUI_Media: <https://github.com/naowh-gaming/NaowhUI>
- NaowhUI_EUI: <https://github.com/nwh-gaming-ab/NaowhUI_EUI>

```
Copyright © 2026 The contents of these addons, excluding externals listed below, are
copyrighted to their authors with all rights reserved.
```

The original license files ship unchanged in each folder (`NaowhUI/LICENSE.md`,
`NaowhUI_Data/LICENSE.md`, `NaowhUI_EUI/LICENSE.md`, `NaowhUI_Media/LICENSE.md`). The MIT
license below does **not** apply to Naowh's code, profiles, strings, textures, sounds,
logos or names. All of those stay the property of their authors. If the authors ask for
this port to be changed or removed, it will be.

The NaowhUI fonts (`GothamNarrowUltra*.ttf`, `Naowh*.ttf`) are **not** included. Copy them
from the official NaowhUI_Media release (see `NaowhUI_Media/Shared/Fonts/README.md`).

## 2. WeakAuras by Merfin

The class WeakAuras in `NaowhUI_Data/TBC/WeakAuras/Classes` are **Merfin's** WotLK class
WeakAuras (<https://www.merfin.net>), re-anchored to EllesmereUI frames for 3.3.5a. They remain
the work and property of Merfin.

## 3. Third-party libraries

These keep their own licenses:

| Library | License |
|---|---|
| LibStub | Public domain |
| CallbackHandler-1.0 | BSD |
| LibSharedMedia-3.0 | LGPL 2.1 |

## 4. 3.3.5a port work: MIT

Only the changes made to run NaowhUI on the WoW 3.3.5a client (build 12340) are released
under the MIT license. That covers:

- New files: `NaowhUI/Compat_335.lua`, `NaowhUI_Media/Compat_335.lua`,
  everything under `NaowhUI/Game/Wrath/`, `NaowhUI_Data/NaowhUI_Data.toc`,
  `NaowhUI_Data/TBC/WeakAuras/Classes/DeathKnight.lua` (anchor changes only; the auras are
  Merfin's).
- The 3.3.5a modifications (not the original code) in the TOC files, the `Game/Shared`
  installer and setup files, and the `NaowhUI_EUI` modules and QoL files.

```
MIT License

Copyright (c) 2026 Laraystiri (Darksummonex)

Permission is hereby granted, free of charge, to any person obtaining a copy of the 3.3.5a
port modifications described above (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

This project is not affiliated with or endorsed by Naowh, NWH Gaming AB, Merfin or Blizzard
Entertainment.
