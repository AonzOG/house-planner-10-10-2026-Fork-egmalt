# House Planner installer v1.0.2 - Windows occupied-port handling

## Maintainer-reported Windows BAT installation — 10 October 2026

**Reported result:** After receiving installer v1.0.2, the repository maintainer stated: "The Windows bat installer works." This records a **maintainer-reported successful Windows BAT installation**, not an independent native-Windows execution by the authoring environment. No installer code was changed as part of recording this report.

**Earlier Windows observations:** The v1.0 installer failed to pass arguments to Docker. Version 1.0.1 correctly ran `docker compose version` (v5.5.1) and `docker info --format {{.OSType}}` (`linux`), but then stopped because port 8080 was occupied. Version 1.0.2 added the alternative-port prompt and renamed the second selection to "Back up Fork."

**Evidence boundaries:** The maintainer's confirmation does not, by itself, independently validate the exact selected source, setup-key display, completed first-run password setup, browser rendering, saved-plan persistence, Repair, Uninstall, failed-update rollback, or source switching. Linux and macOS native installers remain unverified. The statements below that Windows was "not native-runtime tested" accurately describe the earlier development-environment tests; they are retained as historical findings rather than silently rewritten.

---

**Observed:** At 22:40:39 on 10 October 2026, the v1.0.1 Windows log showed `docker compose version` => v5.5.1, and `docker info --format {{.OSType}}` => `linux`. Docker runtime prerequisite detection **passed on the user's Windows computer**. At 22:40:41, installation stopped at the new `Assert-PortFree 8080` check because an existing process owns that loopback port. This is a valid environmental conflict, not a regression in Docker detection. No source archive was acquired before this stop.

**Scoped changes in v1.0.2:**

- Added `Test-PortFree` and `Find-AvailablePort` to probe loopback ports without modifying existing services; search up to 128 consecutive candidate ports, beginning at requested+1.
- Added wizard `Confirm-GuiPort` at directory-page Next and requirements-page Begin. On collision, offer the free alternative with a Yes/No prompt; Yes updates the chosen port; No preserves manual choice and does not start a failing install. For Repair, the saved port is exempt from the preflight test because a running owned container may occupy it.
- Kept worker-side port validation as a second guard and improved its diagnostics when the port is claimed between GUI and worker preflights.
- Changed the user-facing source label from `Your fork` to `Back up Fork` across the Windows, Linux and macOS repo-selection prompts and documentation. No change to repository URLs, internal `Original`/`Fork` enum values, manifest/volume IDs or existing data.
- Bumped installer log version to v1.0.2.

**Frozen known-good behavior:** `Invoke-Program` command-argument repair from v1.0.1; Docker Compose commands; source acquisition and pinned revision; app-local path safeguards; ownership lists; user volume persistence; repair rollback; uninstall.

**v1.0.2 checks performed in this session:** 34/34 targeted source/shell/logic regression checks passed using `test_hp_102.py`. These include `bash -n` for the Linux/macOS/core shells, source-label mapping evaluated via Bash for both options on Linux and macOS, package invariants, preserved Docker command arguments, unchanged Docker bind and ownership/volume semantics, PowerShell lexical tokenization (not a PowerShell parser), and a loopback occupied-port fixture under Linux. Windows PowerShell 5.1, WinForms dialogs, Docker Desktop and real House Planner image builds are not available locally, so **native Windows end-to-end validation is still outstanding**. There is an unavoidable time-of-check-to-time-of-use gap between testing a port and starting Docker; a second worker-side check catches most races but cannot prevent another process from claiming the port just before Docker binds it.

**Remaining checks:** The PowerShell 5.1/WinForms GUI could not be executed natively in Linux. Source-level and lexical checks are not a substitute for parsing or exercising it on Windows. A genuine Docker image build, HTTP UI smoke, saved-plan test, repair test and uninstall test remain **not native-runtime tested** for the new version.

---

# Version 1.0.1 Windows Docker Invocation Patch

**Reported failure:** 10 October 2026 at 22:35:32 Fiji; installation into `C:\house-planner` stopped during Docker preflight. Logs showed *Running docker.exe* with a blank argument list twice, followed by Docker's help text and a misleading Linux-engine failure.

**Verified source-level cause:** `Invoke-Program` defined its command-array parameter as `[string[]]$Args`. `$args` is an automatic variable in Windows PowerShell, which is overwritten with the function's unbound arguments. The function therefore passed an empty command-line string into `ProcessStartInfo.Arguments`. This agrees with the exact observed log.

**Changed:** renamed the function argument array to `$CommandArguments`; added an invariant rejecting zero-argument external invocations; renamed the GUI worker-local `$args` to `$workerArguments` as a preventive clarity change; bumped displayed version to 1.0.1.

**Unchanged:** all source URLs/revision policy, Docker Compose commands, local loopback port binding, data volume preservation, cancellation, filesystem safeguards, Repair rollback and Uninstall procedures. Non-Windows scripts are byte-for-byte identical to 1.0.

**Validation:** source comparisons, argument-call inspection, security invariants, package/checksum consistency, and Unix shell syntax checks were run. PowerShell 5.1 was not present in the Linux build environment. **Statically validated, not native-runtime tested.** The next acceptance gate is running the updated installer on Windows and checking that both Docker subcommands and the actual engine status appear in its logs.

---

# House Planner installer: evidence and verification

Assessment date: 2026-10-10 (Fiji time)

## Repository verification

Inspected through the connected GitHub repository service:

- `egmalt/house-planner` and `AonzOG/house-planner-10-10-2026-Fork-egmalt` both expose a populated public default branch `main`.
- At assessment time, both default branches resolved to commit and root tree `5c91280da6c5cc84c1a534ef80ddafb64a6b5baa`. Each full tree contains 320 files and 49 directories (truncated=false).
- Read upstream root `README.md`, `docs/guide/en/install.md`, `docs/guide/en/deploy.md`, `package.json`, `Dockerfile`, `docker-compose.yml`, Docker entrypoint/boot, PHP setup/init, and source storage/development router.
- Source build path: `node:22-alpine`, `npm ci`, `npm run build`; runtime: `php:8.3-apache`; service container port 8080; persistent named Docker volume storing credentials and plan/version/snapshot data.
- Deliberate correction: don't use Vite development mode as an installed production application. Generate a per-installation Docker Compose production configuration and keep the password/plan Docker volume persistent.

## Passing checks (performed in this Linux container)

1. `bash -n` for `HousePlanner-Unix-Core.sh`, the Linux GUI/terminal wrapper and the macOS dialog wrapper: **PASS**.
2. Windows PS1 scanned with Pygments PowerShell lexical analyzer: no lexical error tokens; **not equivalent to parsing or executing the PS1**.
3. The generated Compose YAML parsed by PyYAML; confirmed `127.0.0.1:19089:8080` mapping and a dedicated persistent data volume: **PASS**.
4. Isolated mock-based Linux install using a directory whose path includes an apostrophe and spaces: **PASS**.
5. Repair from Original to Fork with a user-edited source file: new repository attribution recorded, previous edited source retained: **PASS**.
6. Forced Docker build failure during the next Repair: nonzero result, prior manifest/source restored, image restore attempted, volume was not removed: **PASS**.
7. Uninstall using deterministic mock Docker: removes application-owned files but preserves unrelated files and altered source backup; no `down -v` or volume deletion: **PASS**.
8. Explicitly rejected dangerous installation roots `/`, `$HOME`, `/usr`: **PASS**.
9. Download URLs constrained to allowlisted GitHub repositories and exact 40-character commit SHA; TLS checks enabled; manifest and source-file hashes checked for owned file removal: **reviewed and partially test-covered**.

## Outstanding acceptance tests / limitations

- No Windows host or `powershell.exe`/`pwsh` available. **WinForms wizard, embedded PowerShell parsing, Docker Desktop integration, and Windows install/repair/uninstall are not native-runtime tested.** Run PowerShell Parser (`[System.Management.Automation.Language.Parser]::ParseFile`) and full install/repair/uninstall on Windows with Docker Desktop.
- No macOS host or AppleScript runtime. macOS dialogues, `.command` launch behaviour and Docker Desktop compatibility are **not native-runtime tested**. Verify on supported Intel and Apple Silicon Macs.
- `docker` binary/server and direct GitHub source downloads are not available in the test environment. The core's end-to-end tests used controlled command stubs, not a real registry, Docker build, npm dependency installation or actual HTTP application process.
- A complete `npm audit`, vulnerability analysis of npm dependencies, Docker images, signatures, and runtime security assessment was **not performed**. Do not infer that the installer or upstream application is vulnerability-free.
- GitHub ZIP hash is recorded after download but there is no independent published ZIP SHA256/signature used for verification; a pinned Git SHA is useful for reproducible source selection but is not a cryptographic verification of the archive by itself.

## Native end-to-end test checklist

For each supported OS: (1) install and start Docker; (2) install the Original from a folder with a space/apostrophe; (3) confirm a live browser UI at localhost and finish first-run setup; (4) save a plan and snapshot; (5) Repair at the same commit; (6) switch source to Fork and re-test; (7) force a failing repair and verify rollback; (8) uninstall and check that saved plans remain in the named Docker volume; (9) reinstall at the same root and confirm prior plans/password remain; (10) verify edited/untracked files and unrelated files were not deleted.

**Overall state: shell-syntax checked and mock-workflow tested; Windows/macOS components statically inspected, not native-runtime tested.**
