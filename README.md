Run a server scene and a few clients (see the ps1 script for examples). Move around with clients, jump with space, close the client(s) and see others move around etc.

Server has a camera too in non-headless mode, so you can see what the server view is of those players. Note that its more choppy because server updates per-tick, while player movements are smoothed client-side.

Useful server scripts:

- `.\run_orchestrator.ps1`
- `.\run_zone.ps1 --zone mvp --port 4242`
- `.\run_servers.ps1`

Add `--headless` to `run_zone.ps1` or `run_servers.ps1` only when you want Godot zones to run headless.
