# k6 Blackbox Load Tester

CLI-based load tester for blackbox website testing using k6 in Docker.

## What it supports

- Input target URLs/endpoints interactively or via config file.
- Gradual load increase using k6 stages (ramp-up / ramp-down).
- Real-time metrics in terminal and web dashboard.
- Documented reports after each run (`summary.json`, `raw.json`, `dashboard.html`, `report.md`).
- Custom request headers you define (global and per-endpoint).

## Requirements

- Docker Desktop
- PowerShell (Windows)

## Quick start

1. Optional: copy and edit config:
   - `k6/config.example.json` -> `k6/config.json`
2. Run interactive wizard:
   - `.\run.ps1`
3. Or run with existing config:
   - `.\run.ps1 -ConfigPath .\k6\config.json -NoPrompt`

### Git Bash

If you use Git Bash, do not run `./run.ps1` directly (bash will try to parse PowerShell syntax).

- Use wrapper: `./run.sh -ConfigPath ./k6/config.json -NoPrompt`
- Or call PowerShell explicitly:
  - `powershell.exe -ExecutionPolicy Bypass -File ./run.ps1 -ConfigPath ./k6/config.json -NoPrompt`

## Config format

Use `k6/config.example.json` as a template.

Main fields:

- `baseUrl`: base URL for relative endpoint paths.
- `headers`: custom headers for all requests.
- `stages`: load ramp profile.
- `thresholds`: pass/fail SLAs.
- `endpoints`: list of URLs to hit.

Each endpoint supports:

- `name`
- `method`
- `url` (absolute URL or relative path)
- `headers` (optional endpoint-level headers)
- `body` (for POST/PUT/PATCH)
- `expectedStatus` (e.g. `[200, 204]`)
- `weight` (weighted random traffic distribution)
- `timeout`
- `sleepSeconds`

## Output artifacts

Every run creates `reports/<timestamp>/`:

- `summary.json`: k6 final summary
- `raw.json`: streaming metrics
- `dashboard.html`: exported dashboard
- `report.md`: human-readable report

