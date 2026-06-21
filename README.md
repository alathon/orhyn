Run a server scene and a few clients. Move around with clients, jump with space, close the client(s) and see others move around etc.

Server has a camera too in non-headless mode, so you can see what the server view is of those players. Note that its more choppy because server updates per-tick, while player movements are smoothed client-side.

Useful server commands:

- `make orchestrator`
- `make zone ARGS="--zone mvp --port 4242"`
- `make servers`
- `make server-and-client`

Add `ARGS="--headless"` to `make zone` or `make servers` only when you want Godot zones to run headless. Direct shell and PowerShell launchers live in `scripts/`. Grouped launch commands stream prefixed output to the terminal, tee logs under `logs/`, and stop all child processes on Ctrl-C. Override the log directory with `ORHYN_LOG_DIR=/path/to/logs`.
