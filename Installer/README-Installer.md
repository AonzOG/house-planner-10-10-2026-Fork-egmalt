# House Planner Dual-Source Installer - Version 1.0.2

## Windows port selection repair (10 October 2026)

The v1.0.1 Windows log established that Docker Compose v5.5.1 and the Linux engine are responding correctly. The new stop at port 8080 was a real local port conflict, not a Docker or source-code failure. Version 1.0.2 preserves the working Docker argument handling and now checks the chosen port *before* proceeding past the installation directory page. If the port is occupied, the wizard offers the next available nearby port, starting with 8081 for a conflict on 8080. Click **Yes** to use it, or **No** to keep the page open and select your own port. The wizard rechecks just before Begin, and the background worker independently checks before making changes. It never stops the service that occupies the original port.

The source-choice label is **Back up Fork** (same repository URL and internal source identity `Fork`) on Windows, Linux and macOS. The two repository URLs, pinned-commit/repair behavior, Docker commands, local-loopback binding, data-volume preservation, and uninstall guards are not changed.

**To install on Windows:** extract this ZIP into a new folder, open `Install House Planner - Windows.bat`, select Original or Back up Fork, and keep the installation directory `C:\house-planner` or use Browse. The wizard offers a free alternative automatically when the selected port is taken. No Docker reinstallation is required for the reported failure.

**Validation:** Linux shell syntax and targeted source-level/regression/package checks passed; the Windows wizard is statically validated but **not native-runtime tested** in this environment. A full native Windows Docker install remains the acceptance test.

---

# House Planner Dual-Repository Installer

Version 1.0.1 | 10 October 2026 | Two selectable GitHub sources

## Windows fix in version 1.0.1 (Docker arguments)

This maintenance release fixes the Windows bootstrap bug identified from the 22:35:32 installer log: the Docker command wrapper used a PowerShell function parameter named `$Args`, which collides with PowerShell's automatic `$args` variable. Docker was therefore invoked without `compose version`, `info --format '{{.OSType}}'`, or subsequent intended command arguments. The resulting *Docker Linux engine is not ready* message was not a valid check of the engine.

The patch renames the parameter to `$CommandArguments`, refuses any attempted zero-argument command invocation, renames the GUI worker argument array to `$workerArguments` for clarity, and logs release `1.0.1`. No change was made to the repository URLs, exact-commit source selection, build/deploy commands, Docker Compose isolation, data-volume ownership, Repair, or Uninstall behaviour.

**For the original failed attempt:** extract this version into a new folder, then double-click `Install House Planner - Windows.bat`. Keep installation mode **Install** and directory `C:\house-planner`, if the first attempt did not leave an installation manifest there (the reported failure was before any source files were installed). If an existing manifest exists, select Repair instead. You do not need to uninstall or change Docker solely because of the earlier empty-command error.

After repair, the log should show `Running docker.exe "compose" "version"` and `Running docker.exe "info" "--format" "{{.OSType}}"`, followed by actual Compose version and `linux` output when Docker is ready. If the Docker daemon genuinely is unavailable, Docker will now print its real error and the installer will stop before downloading/building application source.

**Native Windows smoke testing remains outstanding.** This patch has been statically checked in Linux; a real PowerShell 5.1/Windows Docker execution is required to confirm target-machine success.

## Download, install, open

Unpack the complete ZIP before starting. Keep the installer files together in the same folder.

| OS | Start this file | Initial default installation folder |
|---|---|---|
| Windows 10/11 | Double-click `Install House Planner - Windows.bat` | `C:\house-planner` (editable with **Browse**) |
| Linux desktop | `bash "Install House Planner - Linux.sh"` | `~/.local/share/house-planner` |
| macOS | Double-click `Install House Planner - macOS.command` or run it in Terminal | `~/Library/Application Support/house-planner` |

Windows opens a multi-page PowerShell WinForms wizard. Linux uses Zenity native dialogs when Zenity and a GUI session are available; otherwise, it uses an interactive terminal fallback. macOS uses AppleScript dialogs and Terminal-based progress. This package is not a signed Windows EXE, MSI, Apple .app, PKG or DMG.

### Before starting

Install and start Docker Desktop (Windows/macOS) or a usable Docker Engine with the Docker Compose v2 plugin (Linux). The Docker engine **must support Linux containers**. On Windows, Docker Desktop's WSL2 backend is suitable. Your current user must have the permissions needed to run Docker. Installing or enabling the system-level Docker dependency is left to the user, intentionally; the installer does not silently add privileged services, machine-wide PATH entries or drivers. Docker will download Node 22 and PHP 8.3/Apache base images as part of the application build. The build also retrieves the Node package dependencies pinned by the repository's `package-lock.json`.

### Source selection in the wizard

Choose one of these, on its own page:

- **Original:** `https://github.com/egmalt/house-planner`
- **Back up Fork:** `https://github.com/AonzOG/house-planner-10-10-2026-Fork-egmalt`

The installer resolves a real SHA from the selected repository's `main` branch, downloads its GitHub source archive at that SHA, and builds that specific source into the application's local Docker image. Neither selection secretly installs the other source. The chosen repo and commit are recorded in the local manifest. As verified on 10 October 2026, the two repositories happen to have identical `main` contents and commit `5c91280da6c5cc84c1a534ef80ddafb64a6b5baa`; the source selection remains significant for future changes.

### First run

The installer runs the production Docker Compose build, starts the service, and checks its HTTP endpoint. Browse to `http://127.0.0.1:8080/api/setup.php` (replace `8080` with your chosen port). The installation wizard displays a random setup key, also saved in `.env` under the installation directory. Enter the key, choose your application password (8+ characters), and complete House Planner's built-in setup. After first setup, the setup endpoint is normally locked and responds with HTTP 403; this is expected. If you repair or reinstall using the same preserved Docker data volume, the previous password and projects remain, so you normally just sign in.

The installer binds the container's published port to IPv4 loopback (`127.0.0.1`) to avoid unexpected LAN exposure. Remote deployment requires a separate, deliberate reverse-proxy/HTTPS/security configuration. Do not forward this unencrypted local service directly to the internet.

## Manage, repair, and uninstall

**Start**: use the generated `Start House Planner.bat` (Windows), `Start House Planner.sh` (Linux) or `Start House Planner.command` (macOS) in the installation folder. It starts the existing local container without rebuilding, checks availability, and opens the browser.

**Repair / update / switch repo**: open the installed `Manage House Planner.bat` on Windows, or the corresponding installed `Install House Planner - Linux.sh` / `Install House Planner - macOS.command`. Choose **Repair**, select the desired source (including switching Original <-> Fork), and optionally enable **latest commit**. The default for a same-repository repair is the installed commit, not unreviewed new code. Repair stages the new source, saves the previous image for rollback when available, and preserves the existing Docker named volume. Edited/untracked previous source is copied into `source-previous-*`; a failed build attempts to restore the old source, configuration, and previous Docker image. Back up projects separately before major updates.

**Uninstall**: choose Uninstall from the corresponding wizard. It stops/removes **this installation's** Docker containers and attempts to remove the managed local application image. It does **not** run `docker compose down -v` and does **not** delete the named volume. Plans, version history, snapshots and House Planner's password configuration remain there. Existing Docker/Node/PHP system installations are not modified or removed. User-modified/untracked downloaded source files and unrelated files are retained; the installation root is not recursively removed indiscriminately. Generated installer management files and the local setup key are removed when uninstall completes.

For independent installations in different directories, the installer assigns separate Docker Compose project identifiers, container networks, image tags and named data volumes. They may need distinct local host ports (for example 8080 and 8081). The Docker volume name is recorded in the installation manifest and diagnostic log.

**Important:** Preserved Docker volumes are intentional. Do not manually delete a volume until you have explicitly identified it and securely backed up all plans. The installer does not implement a destructive volume-wipe option.

## Application internals and trust limits

- House Planner is a React/TypeScript/Vite client and PHP API. Its supported production Dockerfile builds with Node.js 22 and serves with PHP 8.3/Apache. A native Windows/macOS desktop app was **not** provided by either repository.
- The Docker build runs `npm ci` using the selected repo's lockfile. It **does not** use `npm run dev` as a permanent production service.
- HTTPS/TLS validation is not disabled. GitHub source SHA and downloaded ZIP SHA-256 are logged; the ZIP SHA-256 is for traceability, **not an independent vendor signature or a published checksum verification**. Docker base images and npm package downloads remain part of the supply-chain trust boundary.
- Docker grants the selected repository's Dockerfile authority to execute build commands within the Docker build environment. Only install from repositories and commits you trust.
- The wizard does not configure remote access, HTTPS, authentication beyond the upstream first-run wizard, backups, auto-updates, third-party Docker installation, or commercial deployment.
- Optional Petrovich shopping-cart integration in the underlying app may require PHP cURL support; the Docker image is determined by the upstream Dockerfile.

## Troubleshooting

1. If Docker is missing or not ready, start Docker Desktop/Engine in Linux-container mode and retry. The Windows **Docker Desktop website** button opens Docker's setup guide; it does not install software automatically.
2. If your selected port is occupied, use a different one for new installations. For Repair, keep the saved port unless you intend to change it.
3. If a build fails (download error, npm error, Docker daemon permissions, disk space), inspect the **diagnostic log** in the installer GUI or system log folder. Windows logs are under `%LOCALAPPDATA%\HousePlannerInstaller\logs`; Linux under `${XDG_STATE_HOME:-$HOME/.local/state}/house-planner-installer/logs`; macOS under `~/Library/Logs/HousePlannerInstaller`.
4. If the setup page returns 403 but the application loads, initialization is already complete. Sign in using the prior application password. Do not expect a new setup key to reset the old password.
5. Use an empty folder for the initial install. An unrelated folder with files is rejected to avoid overwrites. Do not place the app under a filesystem symlink/junction, drive root, or protected system directory.
6. The macOS script is unsigned and not notarized. Normal macOS security controls apply; the installer does not disable them. Docker Desktop may require separate installation approval.

## Verification status

The Linux core has been tested locally against deterministic **mock GitHub/HTTP/Docker commands** for installation, source switching, repair, intentionally failed-build rollback, path quoting and uninstall data preservation. Generated Docker Compose YAML was parsed successfully. The Unix shell scripts passed `bash -n`. The Windows PowerShell was lexically checked but cannot be executed or parsed by real Windows PowerShell in this build environment, and macOS AppleScript dialogs were not executed. **No genuine Docker image build, Windows GUI run, macOS run, or full native end-to-end installation was tested here.** See `VALIDATION-REPORT.md` for exact scope.

## Project links

- Original: https://github.com/egmalt/house-planner
- Back up Fork: https://github.com/AonzOG/house-planner-10-10-2026-Fork-egmalt
- Official install guide: https://github.com/egmalt/house-planner/blob/main/docs/guide/en/install.md
- Docker Desktop: https://docs.docker.com/desktop/

Both source repositories are MIT licensed. Original authors' notices and third-party model/texture licenses in the downloaded sources are retained and not replaced by this installer.
