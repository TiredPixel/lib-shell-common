# Common library for Shell

Common library for Shell, containing miscellaneous scripts for packaging, etc.

## Requirements

Bash 4.4 or newer. Every script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. macOS ships 3.2 as `/bin/bash`; install a current one and keep it ahead of `/bin` on `PATH`.

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
