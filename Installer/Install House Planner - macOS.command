#!/usr/bin/env bash
# House Planner dual-source macOS GUI dialogs (AppleScript) plus terminal progress.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CORE="$HERE/HousePlanner-Unix-Core.sh"
[[ -f "$CORE" ]] || { echo 'HousePlanner-Unix-Core.sh must be beside this script.' >&2; exit 1; }
DEFAULT="$HOME/Library/Application Support/house-planner"
[[ -f "$HERE/.hp-install-manifest" ]] && DEFAULT="$HERE"
MODE="$(osascript <<'AS'
set answer to choose from list {"Install", "Repair", "Uninstall"} with title "House Planner Setup" with prompt "Choose what to do with House Planner:"
if answer is false then return ""
return item 1 of answer
AS
)" || exit 0
[[ -n "$MODE" ]] || exit 0
SOURCE=Original
if [[ "$MODE" != Uninstall ]]; then
  SRC="$(osascript <<'AS'
set answer to choose from list {"Original - egmalt/house-planner", "Back up Fork - AonzOG/house-planner-10-10-2026-Fork-egmalt"} with title "Choose GitHub repository" with prompt "Select where to download the House Planner source:"
if answer is false then return ""
return item 1 of answer
AS
)" || exit 0
  case "$SRC" in Original*) SOURCE=Original;; 'Back up Fork'*) SOURCE=Fork;; *) exit 0;; esac
fi
ROOT="$(osascript - "$DEFAULT" <<'AS'
on run argv
  set d to item 1 of argv
  set r to display dialog "Choose an application-specific installation folder. Click Browse for an existing location, or type a new absolute path." default answer d buttons {"Cancel", "Browse...", "Continue"} default button "Continue" with title "House Planner installation location"
  if button returned of r is "Browse..." then
    return POSIX path of (choose folder with prompt "Choose installation folder")
  end if
  return text returned of r
end run
AS
)" || exit 0
[[ -n "$ROOT" ]] || exit 0
PORT=8080 UPDATE=no
if [[ "$MODE" == Repair && -f "$ROOT/.hp-install-manifest" ]]; then
  oldport="$(sed -n 's/^HP_PORT=//p' "$ROOT/.hp-install-manifest" | head -n 1)"
  [[ "$oldport" =~ ^[0-9]+$ ]] && PORT="$oldport"
fi
if [[ "$MODE" != Uninstall ]]; then
  PORT="$(osascript - "$PORT" <<'AS'
on run argv
  return text returned of (display dialog "Local HTTP port for 127.0.0.1 (1024 to 65535)" default answer (item 1 of argv) buttons {"Cancel", "Continue"} default button "Continue" with title "Local service port")
end run
AS
)" || exit 0
  if [[ "$MODE" == Repair ]]; then
    if osascript -e 'display dialog "Update to the latest GitHub commit? Cancel keeps the installed commit for repair." buttons {"Keep installed", "Update"} default button "Keep installed" with title "Repair source version"' -e 'if button returned of result is "Update" then return "yes"' | grep -q yes; then UPDATE=yes; fi
  fi
else
  osascript -e 'display dialog "Uninstall the House Planner app and its containers? All house plans, versions, snapshots and settings in the Docker volume will be PRESERVED." buttons {"Cancel", "Uninstall"} default button "Cancel" with title "Confirm uninstall"' >/dev/null || exit 0
fi
osascript -e 'display dialog "Docker Desktop/Engine and Docker Compose v2 must be installed and running Linux containers. This wizard does not install system dependencies. Continue?" buttons {"Cancel", "Continue"} default button "Continue" with title "Prerequisites"' >/dev/null || exit 0
osascript -e 'display notification "Installing source and building Docker image. Progress is visible in Terminal." with title "House Planner"' || :
echo "House Planner: $MODE ($SOURCE), location: $ROOT"
if bash "$CORE" "$MODE" "$ROOT" "$SOURCE" "$PORT" "$UPDATE"; then
  if [[ "$MODE" == Uninstall ]]; then
    osascript -e 'display dialog "Application and its containers removed. Docker volume with saved house plans was preserved." buttons {"Done"} default button "Done" with title "Uninstall complete"' || :
  else
    KEY="$(sed -n 's/^HOUSE_SETUP_KEY=//p' "$ROOT/.env" | head -n 1)"
    osascript - "$KEY" "$PORT" <<'AS'
on run argv
  set k to item 1 of argv
  set p to item 2 of argv
  set r to display dialog "House Planner has been installed at http://127.0.0.1:" & p & "/ . Copy the setup key below, then open the setup page and choose a password." default answer k buttons {"Done", "Copy key and open setup"} default button "Copy key and open setup" with title "House Planner installed"
  if button returned of r is "Copy key and open setup" then
    set the clipboard to k
    do shell script "open http://127.0.0.1:" & p & "/api/setup.php"
  end if
end run
AS
  fi
else
  osascript -e 'display dialog "House Planner operation failed. Review the diagnostic log path and error details printed in Terminal." buttons {"OK"} default button "OK" with title "Installer error"' || :
  exit 1
fi
