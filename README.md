# strata-ctl

Menu-bar start/stop widget for the local [Strata](https://github.com/dark5un/Strata)
server on macOS. A tiny resident app (one Swift file, no dependencies beyond
Cocoa): it watches Strata's `/health` endpoint and shows the state as a
menu-bar emblem — outlined bands (stopped), dashed (loading), filled
(running). Click it to start / stop / restart the server, switch between
model variants, or open the web UI.

Companion to Strata (Windows/Linux focus); this is the Mac-side control.

## What it does

```
polls  http://127.0.0.1:8080/health  every 5s
Start    cd $STRATA_DIR && .venv/bin/python serve/server.py --engine strata --config <variant> --port <port>
Stop     pkill -f 'serve/server.py --engine strata --config <variant>'   (exact match: touches nothing else)
Model    IQ3_XXS (general)  <->  IQ1_M Coder (512K); switching restarts the server on the other config
Open     the Strata web UI in your browser
```

The two model variants reference config files inside the Strata checkout
(`strata-iq3_xxs-1m.json`, `strata-coder-iq1_m-512k.json`). Those are the
variant configs Strata's setup generates; if yours are named differently,
edit the `variants` list at the top of `Sources/main.swift` and rebuild.

## Install

### Download

Grab the latest notarized build from
[Releases](https://github.com/dark5un/strata-ctl/releases):

```sh
tar xzf strata-ctl-<version>-macos.tar.gz && cd strata-ctl && ./install.sh
```

Releases are Developer ID-signed and notarized: Gatekeeper opens them with a
plain double-click.

### From source

Requirements: macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh && open StrataCtl.app
```

## Configuration

No config file — two environment variables, read at launch:

| Var | Default | Meaning |
| --- | --- | --- |
| `STRATA_DIR` | `~/Projects/Strata` | where the Strata checkout lives |
| `STRATA_PORT` | `8080` | the server port (health URL + launch flag) |

Example (launchctl env, or just start it from a shell that exports them):

```sh
STRATA_DIR=~/src/Strata STRATA_PORT=11434 open StrataCtl.app
```

The selected model variant persists in UserDefaults (`strata.variant`).

## Security notes

- Talks only to `127.0.0.1` — no outbound network, no keys, nothing leaves
  the machine.
- The only shell-outs are the two fixed command templates above; no user
  text is interpolated into them (`STRATA_DIR`/`STRATA_PORT` come from your
  own environment — same trust level as the rest of your shell).
- `pkill -f` is anchored to the exact server command line for the selected
  variant, so it cannot match unrelated processes beyond another instance of
  the same Strata server.
- Hardened-runtime compatible (no JIT, no dylib loading); ad-hoc or Developer
  ID signing both work.

## Development

```sh
./build.sh          # -> stratactl + StrataCtl.app (local dev identity, else ad-hoc)
./make_package.sh   # -> dist/ universal tar.gz + dmg
```

MIT
