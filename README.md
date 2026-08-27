# KGB Zombie Escape Core

KGB Zombie Escape Core is a public, GPL-licensed AMX Mod X plugin for a
ReGameDLL-backed Counter-Strike 1.6 Zombie Escape release candidate. It is not
restricted to KGB Hosting customers: operators may run, study, modify, and
redistribute it under GPL-3.0-or-later.

Version `0.1.2` implements the stock-assets gameplay core only:

- delayed random initial infection with a configurable zombie ratio;
- knife-hit infection and CT/T role assignment;
- configurable human and zombie health, armor, gravity, speed, and stock
  weapon loadouts;
- delayed zombie respawn, including the sole-zombie elimination case;
- one-shot ReAPI round termination when no living humans remain;
- player status plus admin status and manual-infection commands; and
- configurable display name and chat prefix.

It does not distribute Zombie Escape maps, models, sounds, sprites, or FastDL
content. Operators remain responsible for obtaining every map and referenced
asset under suitable redistribution terms.

## Runtime contract

The plugin requires ReGameDLL_CS, ReAPI, and AMX Mod X 1.8.2 or newer. The managed
configuration sets `mp_round_infinite "bf"`: ReGameDLL documents `b` as the
needed-player round-end guard and `f` as the team-extermination guard. This
keeps the all-CT pre-infection phase alive and lets a killed sole zombie reach
the delayed respawn callback. Other scenario endings remain available to a
properly licensed `ze_*` map.

The plugin fails closed when `mp_round_infinite` is unavailable or does not
contain both required flags.

`v0.1.2` supersedes the `v0.1.0` and `v0.1.1` prereleases. Operators should
not deploy either older prerelease; the Panel catalog pins the newer immutable
source and release asset.

Primary references:

- [ReGameDLL_CS documented CVar flags](https://github.com/rehlds/ReGameDLL_CS/blob/master/dist/game.cfg)
- [ReGameDLL_CS win-condition implementation](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp)
- [ReAPI `rg_round_end` native](https://github.com/rehlds/ReAPI/blob/1c448d06e8c1cebaea061d6b81b94e85f6262649/reapi/extra/amxmodx/scripting/include/reapi_gamedll.inc#L404)

## Build and verify

Docker is required because the official AMX Mod X compiler is a 32-bit Linux
binary. Build the release-compatible artifact with the oldest supported
compiler:

```bash
AMXX_VERSION=1.8.2 ./scripts/build.sh
```

Compile the same source with every supported compiler and run the static
capability checks:

```bash
./scripts/check-source-capabilities.sh
./scripts/check-compatibility.sh
```

The build script pins each AMX Mod X archive and the official ReAPI
`5.29.0.358` include archive by SHA-256, uses a digest-pinned
Debian container without network access during compilation, verifies the AMXX
`XXMA` magic, and writes `compiled/kgb_zombie_escape.amxx.sha256`.

## Configuration and commands

Start from [`configs/kgb_zombie_escape.cfg.example`](configs/kgb_zombie_escape.cfg.example).
The plugin loads `addons/amxmodx/configs/kgb_zombie_escape.cfg`.

- `/ze` shows the current human/zombie counts.
- `amx_ze_status` prints round and role state to an authorized admin.
- `amx_ze_infect <name or #userid>` starts infection immediately and cancels
  any pending automatic initial infection.

## License

The corresponding source and complete GPL-3.0 text are distributed in this
repository. See [`LICENSE`](LICENSE). The license grants software freedoms; it
does not grant trademark rights in KGB Hosting branding.
