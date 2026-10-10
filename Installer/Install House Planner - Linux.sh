#!/usr/bin/env bash
# Native dialog wrapper for Linux; uses Zenity when installed, terminal prompts otherwise.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CORE="$HERE/HousePlanner-Unix-Core.sh"
[[ -f "$CORE" ]] || { echo 'HousePlanner-Unix-Core.sh must be beside this script.' >&2; exit 1; }
DEFAULT="$HOME/.local/share/house-planner"
[[ -f "$HERE/.hp-install-manifest" ]] && DEFAULT="$HERE"
MODE='' SOURCE='Original' ROOT="$DEFAULT" PORT=8080 UPDATE=no
has_gui=no
if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then has_gui=yes; fi

if [[ "$has_gui" == yes ]]; then
  MODE="$(zenity --list --radiolist --title='House Planner Installer' --text='What would you like to do?' --column='Choose' --column='Action' TRUE Install FALSE Repair FALSE Uninstall --width=560 --height=310)" || exit 0
  [[ -n "$MODE" ]] || exit 0
  if [[ "$MODE" != Uninstall ]]; then
    SOURCE="$(zenity --list --radiolist --title='Choose GitHub repository' --text='The installer builds the selected repository from its own commit.' --column='Choose' --column='GitHub repository' TRUE 'Original: egmalt/house-planner' FALSE 'Back up Fork: AonzOG/house-planner-10-10-2026-Fork-egmalt' --width=730 --height=295)" || exit 0
    case "$SOURCE" in Original:*) SOURCE=Original;; 'Back up Fork:'*) SOURCE=Fork;; *) exit 0;; esac
  fi
  ROOT="$(zenity --entry --title='Installation directory' --text='Type an absolute install path, or select Browse in the following dialog. The folder must be empty for new installations.' --entry-text="$DEFAULT" --width=700)" || exit 0
  [[ -n "$ROOT" ]] || exit 0
  if zenity --question --title='Installation directory' --text='Browse for an existing parent/destination folder instead of the typed path?' --ok-label='Browse...' --cancel-label='Keep typed path' --width=510; then
    BROWSED="$(zenity --file-selection --directory --title='Choose House Planner folder' --filename="$HOME/" 2>/dev/null)" || exit 0
    ROOT="$BROWSED"
  fi
  if [[ "$MODE" != Uninstall ]]; then
    if [[ -f "$ROOT/.hp-install-manifest" && "$MODE" == Repair ]]; then
      OLD_PORT="$(sed -n 's/^HP_PORT=//p' "$ROOT/.hp-install-manifest" | head -n 1)"
      [[ "$OLD_PORT" =~ ^[0-9]+$ ]] && PORT="$OLD_PORT"
    fi
    PORT="$(zenity --entry --title='Local server port' --text='Local port for http://127.0.0.1 (1024-65535)' --entry-text="$PORT" --width=430)" || exit 0
    if [[ "$MODE" == Repair ]]; then
      if zenity --question --title='Repair and update' --text='Update to the latest source commit? No keeps the installed commit (recommended for a basic repair).' --ok-label='Update' --cancel-label='Keep installed commit'; then UPDATE=yes; fi
    fi
  else
    zenity --question --title='Confirm House Planner uninstall' --text='Remove the installer-managed app and its containers? House plans, versions and snapshots in Docker data volumes will be PRESERVED.' --ok-label='Uninstall' --cancel-label='Cancel' --width=600 || exit 0
  fi
  zenity --question --title='Docker requirement' --text='Docker Engine/Compose must already be installed and running Linux containers. No Docker/Node/PHP system software will be installed. Continue?' --ok-label='Continue' --cancel-label='Cancel' --width=620 || exit 0
  STATUS="$(mktemp)"
  (
    set +e
    bash "$CORE" "$MODE" "$ROOT" "$SOURCE" "$PORT" "$UPDATE" 2>&1 | while IFS= read -r line; do printf '# %s\n' "$line"; done
    result="${PIPESTATUS[0]}"
    printf '%s' "$result" > "$STATUS"
    printf '100\n'
  ) | zenity --progress --title='House Planner installation' --text='Working... (source, Docker build and health validation)' --pulsate --no-cancel --auto-close --width=690 || :
  CODE="$(cat "$STATUS" 2>/dev/null || echo 1)"
  rm -f "$STATUS"
  LOGDIR="${XDG_STATE_HOME:-$HOME/.local/state}/house-planner-installer/logs"
  LATEST="$(ls -t "$LOGDIR"/setup-*.log 2>/dev/null | head -n 1 || :)"
  if [[ "$CODE" != 0 ]]; then
    zenity --error --title='House Planner operation failed' --text="Operation failed. Inspect and copy diagnostics from: $LATEST" --width=680
    if [[ -f "$LATEST" ]]; then zenity --text-info --title='House Planner diagnostic log' --filename="$LATEST" --width=860 --height=570 || :; fi
    exit 1
  fi
  if [[ "$MODE" == Uninstall ]]; then
    zenity --info --title='Uninstall complete' --text="Application removed. Saved plans remain in the managed Docker data volume. Log: $LATEST" --width=670
  else
    KEY="$(sed -n 's/^HOUSE_SETUP_KEY=//p' "$ROOT/.env" | head -n 1)"
    zenity --info --title='Installation complete' --text="House Planner is available at http://127.0.0.1:$PORT/\nChoose a password on the initial setup page. Your setup key appears next in a selectable field." --width=600
    zenity --entry --title='Copy your one-time setup key' --text='Copy this key. Paste it into the House Planner setup form, then create a password.' --entry-text="$KEY" --width=750 || :
    if zenity --question --title='Launch House Planner' --text='Open the setup page in your browser?' --ok-label='Open setup' --cancel-label='Done'; then
      if command -v xdg-open >/dev/null 2>&1; then xdg-open "http://127.0.0.1:$PORT/api/setup.php"; fi
    fi
  fi
else
  echo 'House Planner dual-source installer (terminal fallback; install Zenity for GUI dialogs).'
  echo 'Choose: 1=Install, 2=Repair, 3=Uninstall'; read -r ans
  case "$ans" in 1) MODE=Install;; 2) MODE=Repair;; 3) MODE=Uninstall;; *) exit 0;; esac
  if [[ "$MODE" != Uninstall ]]; then
    echo 'Choose repository: 1=Original (egmalt), 2=Back up Fork (AonzOG)'; read -r ans
    [[ "$ans" == 2 ]] && SOURCE=Fork
  fi
  printf 'Install folder [%s]: ' "$DEFAULT"; read -r ans; ROOT="${ans:-$DEFAULT}"
  if [[ "$MODE" != Uninstall ]]; then
    if [[ "$MODE" == Repair && -f "$ROOT/.hp-install-manifest" ]]; then
      oldport="$(sed -n 's/^HP_PORT=//p' "$ROOT/.hp-install-manifest" | head -n 1)"
      [[ "$oldport" =~ ^[0-9]+$ ]] && PORT="$oldport"
    fi
    printf 'Local port [%s]: ' "$PORT"; read -r ans; PORT="${ans:-$PORT}"
    if [[ "$MODE" == Repair ]]; then printf 'Update to latest commit? [y/N]: '; read -r ans; [[ "$ans" == y || "$ans" == Y ]] && UPDATE=yes; fi
  else
    printf 'Uninstall the app but preserve Docker plans? [y/N]: '; read -r ans
    [[ "$ans" == y || "$ans" == Y ]] || exit 0
  fi
  echo 'Docker Engine with Compose must already be running (Linux containers).'
  bash "$CORE" "$MODE" "$ROOT" "$SOURCE" "$PORT" "$UPDATE"
  if [[ "$MODE" != Uninstall ]]; then
    echo "Setup URL: http://127.0.0.1:$PORT/api/setup.php"
    echo "Setup key (also in $ROOT/.env): $(sed -n 's/^HOUSE_SETUP_KEY=//p' "$ROOT/.env")"
  fi
fi
