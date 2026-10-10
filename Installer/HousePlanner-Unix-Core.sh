#!/usr/bin/env bash
# House Planner dual-source installer core for Linux and macOS (Bash 3.2+).
set -euo pipefail

HP_ID='org.houseplanner.dualsource.docker.v1'
HP_MODE="${1:-}"
HP_ROOT="${2:-}"
HP_SOURCE="${3:-Original}"
HP_PORT="${4:-8080}"
HP_UPDATE="${5:-no}"
HP_MYDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ "$(uname -s)" == Darwin ]]; then
  HP_LOGDIR="$HOME/Library/Logs/HousePlannerInstaller"
else
  HP_LOGDIR="${XDG_STATE_HOME:-$HOME/.local/state}/house-planner-installer/logs"
fi
mkdir -p "$HP_LOGDIR"
HP_LOG="$HP_LOGDIR/setup-$(date +%Y%m%d-%H%M%S)-$$.log"
HP_TMP=''

hp_log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$HP_LOG" >&2
}
hp_fail() { hp_log "ERROR: $*"; exit 1; }
hp_cleanup() { if [[ -n "$HP_TMP" && -d "$HP_TMP" ]]; then rm -rf -- "$HP_TMP"; fi; }
trap hp_cleanup EXIT

hp_manifest_value() {
  local key="$1" file="$HP_ROOT/.hp-install-manifest" line
  line="$(grep -m1 "^$key=" "$file" 2>/dev/null || :)"
  printf '%s\n' "${line#*=}"
}
hp_validate_root() {
  local target="$1" current
  [[ -n "$target" ]] || hp_fail 'Choose an application installation folder.'
  [[ "$target" = /* ]] || hp_fail 'Choose an absolute installation folder.'
  [[ "$target" != *$'\n'* && "$target" != *$'\r'* ]] || hp_fail 'Newlines in folder names are not supported.'
  case "$target" in /|/usr|/usr/*|/etc|/etc/*|/bin|/bin/*|/sbin|/sbin/*|/System|/System/*|/Library|/Library/*|/Applications|/Applications/*|/opt|/var|/private|/dev|/proc|/sys|/tmp|/home|/Users) hp_fail 'Reserved system root; choose an application-specific directory.';; esac
  [[ "$target" != "$HOME" && "$target" != "$HOME/" && "$target" != "$HOME/.local" && "$target" != "$HOME/Library" ]] || hp_fail 'Your home or general application directory is not a safe install root.'
  [[ "$target" != *'/../'* && "$target" != *'/./'* && "$target" != */.. && "$target" != */. ]] || hp_fail 'Path traversal is not allowed.'
  # Reject links in the entire parent chain, not only the final directory.
  local walk="$target"
  while [[ "$walk" != / && -n "$walk" ]]; do
    [[ ! -L "$walk" ]] || hp_fail 'Installation path contains a filesystem symlink; choose a real directory.'
    walk="${walk%/*}"
    [[ -n "$walk" ]] || walk=/
  done
  if [[ -d "$target" ]]; then
    current="$(cd "$target" && pwd -P)"
    [[ "$current" != / && "$current" != "$HOME" ]] || hp_fail 'Unsafe resolved installation root.'
    case "$current" in /|/usr|/usr/*|/etc|/etc/*|/System|/System/*|/Library|/Library/*|/opt|/opt/*|/var|/var/*|/private|/private/*|/tmp|/dev|/proc|/sys) hp_fail 'Resolved target points into a system location.';; esac
    target="$current"
  fi
  HP_ROOT="${target%/}"
  [[ -n "$HP_ROOT" && "$HP_ROOT" != / ]] || hp_fail 'Unsafe root.'
}
hp_validate_manifest() {
  local path="$HP_ROOT/.hp-install-manifest" project sha port source repo
  [[ -f "$path" && ! -L "$path" ]] || hp_fail "No valid installer manifest: $path"
  [[ "$(hp_manifest_value HP_ID)" == "$HP_ID" ]] || hp_fail 'Installation ownership identity does not match.'
  project="$(hp_manifest_value HP_PROJECT)"; sha="$(hp_manifest_value HP_SHA)"
  port="$(hp_manifest_value HP_PORT)"; source="$(hp_manifest_value HP_SOURCE)"
  repo="$(hp_manifest_value HP_REPO)"
  [[ "$project" =~ ^hp[a-f0-9]{12}$ ]] || hp_fail 'Invalid project in ownership record.'
  [[ "$sha" =~ ^[a-f0-9]{40}$ ]] || hp_fail 'Invalid commit in ownership record.'
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]] || hp_fail 'Invalid port in ownership record.'
  [[ "$source" == Original || "$source" == Fork ]] || hp_fail 'Invalid source identity in ownership record.'
  [[ "$repo" == 'egmalt/house-planner' || "$repo" == 'AonzOG/house-planner-10-10-2026-Fork-egmalt' ]] || hp_fail 'Invalid repository in ownership record.'
}
hp_project() {
  local str="$1" sum
  if command -v sha256sum >/dev/null 2>&1; then sum="$(printf '%s' "$str" | sha256sum)"; else sum="$(printf '%s' "$str" | shasum -a 256)"; fi
  printf 'hp%s\n' "${sum:0:12}"
}
hp_sha256() {
  local file="$1" sum
  if command -v sha256sum >/dev/null 2>&1; then sum="$(sha256sum "$file")"; else sum="$(shasum -a 256 "$file")"; fi
  printf '%s\n' "${sum:0:64}"
}
hp_repo() {
  case "$HP_SOURCE" in
    Original) printf '%s\n' 'egmalt/house-planner';;
    Fork) printf '%s\n' 'AonzOG/house-planner-10-10-2026-Fork-egmalt';;
    *) hp_fail 'Unknown repository source (must be Original or Fork).';;
  esac
}
hp_docker_check() {
  command -v docker >/dev/null 2>&1 || hp_fail 'Docker not found. Install Docker Desktop/Engine with Linux containers and Compose v2.'
  docker compose version >/dev/null || hp_fail 'Docker Compose v2 is not available.'
  local os
  os="$(docker info --format '{{.OSType}}')" || hp_fail 'Docker engine is not running.'
  [[ "$os" == linux ]] || hp_fail 'Docker is not running Linux containers.'
  hp_log 'Docker Linux engine and Compose verified.'
}
hp_compose() {
  local project="$1"; shift
  docker compose -p "$project" --project-directory "$HP_ROOT" --env-file "$HP_ROOT/.env" -f "$HP_ROOT/house-planner.compose.yml" "$@"
}
hp_latest_commit() {
  local repo="$1" json
  json="$(curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --max-time 70 -H 'User-Agent: HousePlanner-DualSource-Installer' "https://api.github.com/repos/$repo/commits/main")" || hp_fail 'Could not retrieve GitHub default-branch commit.'
  local expression='"sha"[[:space:]]*:[[:space:]]*"([a-f0-9]{40})"'
  if [[ "$json" =~ $expression ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; else hp_fail 'GitHub response did not contain a valid commit SHA.'; fi
}
hp_get_source() {
  local repo="$1" commit="$2" archive dir name parent count size
  [[ "$repo" == 'egmalt/house-planner' || "$repo" == 'AonzOG/house-planner-10-10-2026-Fork-egmalt' ]] || hp_fail 'Source repository is not allowlisted.'
  [[ "$commit" =~ ^[a-f0-9]{40}$ ]] || hp_fail 'Invalid commit SHA.'
  HP_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hp-installer.XXXXXXXX")" || hp_fail 'Cannot create temporary install directory.'
  archive="$HP_TMP/selected-source.zip"
  hp_log "Downloading $repo at pinned commit $commit"
  curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 --max-time 900 --proto '=https' --proto-redir '=https' --output "$archive" "https://codeload.github.com/$repo/zip/$commit" || hp_fail 'GitHub source ZIP download failed.'
  hp_log "Downloaded ZIP SHA-256: $(hp_sha256 "$archive") (record only; upstream does not publish a ZIP checksum here)"
  count=0
  while IFS= read -r name || [[ -n "$name" ]]; do
    ((count+=1))
    [[ "$count" -le 6000 ]] || hp_fail 'Unexpected number of ZIP entries.'
    [[ "$name" != /* && "$name" != *'\'* && "$name" != *$'\r'* && "$name" != *$'\t'* ]] || hp_fail 'Unsafe ZIP entry name.'
    [[ ! "$name" =~ (^|/)\.\.(/|$) && ! "$name" =~ (^|/)\.(/|$) ]] || hp_fail 'ZIP contains path traversal.'
    [[ "$name" == */* ]] || hp_fail 'ZIP is missing an enclosing repository folder.'
  done < <(unzip -Z1 "$archive")
  [[ "$count" -gt 0 ]] || hp_fail 'Empty archive.'
  # Info-ZIP's listing exposes the UNIX symlink file type before extraction.
  unzip -Z -l "$archive" > "$HP_TMP/archive-list.txt" || hp_fail 'Cannot inspect archive metadata.'
  if grep -Eq '^l[^[:space:]]*[[:space:]]' "$HP_TMP/archive-list.txt"; then
    hp_fail 'Symlinks in source ZIP are not accepted.'
  fi
  mkdir -p "$HP_TMP/extract"
  unzip -q "$archive" -d "$HP_TMP/extract" || hp_fail 'Could not extract selected GitHub archive.'
  local folders=("$HP_TMP"/extract/*)
  [[ "${#folders[@]}" -eq 1 && -d "${folders[0]}" ]] || hp_fail 'Unexpected archive directory layout.'
  [[ -z "$(find "${folders[0]}" -type l -print -quit)" ]] || hp_fail 'Downloaded source contains symlinks; refusing install.'
  size="$(du -sk "${folders[0]}" | awk '{print $1}')"
  [[ "$size" -lt 524288 ]] || hp_fail 'Unpacked source is larger than 512 MB.'
  dir="${folders[0]}"
  for name in Dockerfile docker-compose.yml package.json package-lock.json public/api/setup.php docker/entrypoint.sh; do
    [[ -f "$dir/$name" ]] || hp_fail "Expected House Planner source file missing: $name"
  done
  grep -Eq '"name"[[:space:]]*:[[:space:]]*"house-planner"' "$dir/package.json" || hp_fail 'Source package identity does not match House Planner.'
  HP_STAGED_SOURCE="$dir"
}
hp_create_compose() {
  local project="$1" port="$2" file="$HP_ROOT/house-planner.compose.yml"
  cat > "$file" <<EOF
# Generated by House Planner Dual-Source Installer. Loopback-only exposure.
services:
  house-planner:
    build:
      context: ./source
      dockerfile: Dockerfile
    image: "house-planner-installer-$project:local"
    ports:
      - "127.0.0.1:$port:8080"
    environment:
      HOUSE_SETUP_KEY: \${HOUSE_SETUP_KEY}
      HOUSE_PASSWORD: ""
      HOUSE_DEMO: ""
    volumes:
      - house-data:/var/lib/house-planner
    restart: unless-stopped
volumes:
  house-data:
EOF
}
hp_make_env() {
  [[ ! -L "$HP_ROOT/.env" ]] || hp_fail 'Setup key file is a symlink; refusing to use it.'
  [[ ! -f "$HP_ROOT/.env" ]] || return 0
  local key
  if command -v openssl >/dev/null 2>&1; then key="$(openssl rand -hex 32)"; else
    if command -v od >/dev/null 2>&1; then key="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"; else hp_fail 'No cryptographic random-key generator is available.'; fi
  fi
  [[ "$key" =~ ^[a-f0-9]{64}$ ]] || hp_fail 'Could not create a strong setup key.'
  (umask 077; printf 'HOUSE_SETUP_KEY=%s\n' "$key" > "$HP_ROOT/.env")
  chmod 600 "$HP_ROOT/.env"
}
hp_save_manifest() {
  local source="$1" repo="$2" sha="$3" project="$4" port="$5" state="$6"
  local file="$HP_ROOT/.hp-install-manifest" temp="$HP_ROOT/.hp-install-manifest.tmp"
  cat > "$temp" <<EOF
HP_ID=$HP_ID
HP_SOURCE=$source
HP_REPO=$repo
HP_SHA=$sha
HP_PROJECT=$project
HP_PORT=$port
HP_VOLUME=${project}_house-data
HP_STATE=$state
EOF
  chmod 600 "$temp"
  mv -f "$temp" "$file"
}
hp_fingerprint() {
  local src="$1" name hash
  (cd "$src"
   find . -type f -print | LC_ALL=C sort | while IFS= read -r name; do
     [[ "$name" != *$'\n'* && "$name" != *$'\t'* ]] || hp_fail 'File name cannot contain tabs/newlines.'
     hash="$(hp_sha256 "$name")" || exit 1
     printf '%s\t%s\n' "$hash" "$name"
   done)
}
hp_save_fingerprint() {
  hp_fingerprint "$HP_ROOT/source" > "$HP_ROOT/.hp-source-files.tsv.tmp"
  mv -f "$HP_ROOT/.hp-source-files.tsv.tmp" "$HP_ROOT/.hp-source-files.tsv"
}
hp_source_changed() {
  [[ -f "$HP_ROOT/.hp-source-files.tsv" && -d "$HP_ROOT/source" ]] || return 0
  [[ -z "$(find "$HP_ROOT/source" -type l -print -quit)" ]] || return 0
  if cmp -s <(hp_fingerprint "$HP_ROOT/source") "$HP_ROOT/.hp-source-files.tsv"; then return 1; else return 0; fi
}
hp_install_launchers() {
  local platform="$1" main="$HP_ROOT/HousePlanner-Unix-Core.sh" src="$HP_MYDIR/HousePlanner-Unix-Core.sh"
  if [[ "$src" != "$main" ]]; then cp "$src" "$main"; fi
  chmod 700 "$main"
  local installer=''
  if [[ "$platform" == Darwin ]]; then
    installer='Install House Planner - macOS.command'
  else
    installer='Install House Planner - Linux.sh'
  fi
  if [[ "$HP_MYDIR/$installer" != "$HP_ROOT/$installer" ]]; then cp "$HP_MYDIR/$installer" "$HP_ROOT/$installer"; fi
  chmod 700 "$HP_ROOT/$installer"
  cat > "$HP_ROOT/Start House Planner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$DIR/HousePlanner-Unix-Core.sh" Launch "$DIR"
EOF
  chmod 700 "$HP_ROOT/Start House Planner.sh"
  if [[ "$platform" == Darwin ]]; then
    cp "$HP_ROOT/Start House Planner.sh" "$HP_ROOT/Start House Planner.command"
    chmod 700 "$HP_ROOT/Start House Planner.command"
  fi
}
hp_check_http() {
  local port="$1" n
  for ((n=0;n<25;n++)); do
    if curl --silent --show-error --fail --max-time 4 --output /dev/null "http://127.0.0.1:$port/" 2>/dev/null; then
      hp_log "Local HTTP application check passed at http://127.0.0.1:$port/"
      return 0
    fi
    sleep 2
  done
  hp_log "HTTP endpoint did not become reachable at 127.0.0.1:$port. Check Docker logs."
  return 1
}
hp_is_empty_dir() {
  [[ ! -d "$1" ]] && return 0
  [[ -z "$(ls -A "$1")" ]]
}
hp_install() {
  local repo sha project stage
  hp_validate_root "$HP_ROOT"
  [[ ! -e "$HP_ROOT/.hp-install-manifest" ]] || hp_fail 'This is already a managed installation. Select Repair.'
  hp_is_empty_dir "$HP_ROOT" || hp_fail 'Installation target is not empty. Choose a new/empty folder.'
  hp_docker_check
  repo="$(hp_repo)"; sha="$(hp_latest_commit "$repo")"; project="$(hp_project "$HP_ROOT")"
  hp_get_source "$repo" "$sha"
  stage="$HP_STAGED_SOURCE"
  mkdir -p "$HP_ROOT"
  mv "$stage" "$HP_ROOT/source"
  hp_create_compose "$project" "$HP_PORT"
  hp_make_env
  hp_install_launchers "$(uname -s)"
  hp_save_fingerprint
  hp_save_manifest "$HP_SOURCE" "$repo" "$sha" "$project" "$HP_PORT" pending
  hp_log "Building selected repository via Docker Compose; source SHA $sha"
  hp_compose "$project" config --quiet || hp_fail 'Generated Compose configuration is invalid.'
  hp_compose "$project" up -d --build || hp_fail 'Docker build failed. Files were retained for Repair; Docker data was not removed.'
  hp_check_http "$HP_PORT" || hp_fail 'Docker started but HTTP validation failed; files were retained for Repair.'
  hp_save_manifest "$HP_SOURCE" "$repo" "$sha" "$project" "$HP_PORT" installed
  hp_log "SUCCESS: House Planner installed from $repo ($sha)"
  hp_log "URL: http://127.0.0.1:$HP_PORT/api/setup.php ; setup key saved in $HP_ROOT/.env"
  hp_log "Data is persistent in Docker volume ${project}_house-data"
}
hp_repair() {
  local repo sha project old new changed oldCompose backupCompose oldImage backupImage haveImage
  hp_validate_root "$HP_ROOT"; hp_validate_manifest
  hp_docker_check
  project="$(hp_manifest_value HP_PROJECT)"
  [[ -d "$HP_ROOT/source" && ! -L "$HP_ROOT/source" ]] || hp_fail 'Owned source folder missing or linked. Cannot repair safely.'
  [[ -f "$HP_ROOT/house-planner.compose.yml" && ! -L "$HP_ROOT/house-planner.compose.yml" ]] || hp_fail 'Missing or linked Compose file; cannot repair safely.'
  hp_make_env
  if [[ "$(hp_manifest_value HP_SOURCE)" == "$HP_SOURCE" && "$HP_UPDATE" != yes ]]; then
    sha="$(hp_manifest_value HP_SHA)"
  else
    sha="$(hp_latest_commit "$(hp_repo)")"
  fi
  repo="$(hp_repo)"
  hp_get_source "$repo" "$sha"
  new="$HP_STAGED_SOURCE"
  oldImage="house-planner-installer-$project:local"
  backupImage="house-planner-installer-$project:previous-$$"
  haveImage=no
  if docker image inspect "$oldImage" >/dev/null 2>&1; then
    docker tag "$oldImage" "$backupImage" || hp_fail 'Cannot snapshot existing Docker image before repair.'
    haveImage=yes
    hp_log "Temporary rollback image preserved: $backupImage"
  fi
  changed=no
  if hp_source_changed; then changed=yes; fi
  old="$HP_ROOT/source-previous-$(date +%Y%m%d-%H%M%S)-$$"
  backupCompose="$HP_TMP/prior-compose.yml"
  cp "$HP_ROOT/house-planner.compose.yml" "$backupCompose"
  cp "$HP_ROOT/.hp-source-files.tsv" "$HP_TMP/prior-source-files.tsv"
  mv "$HP_ROOT/source" "$old"
  if ! mv "$new" "$HP_ROOT/source"; then
    mv "$old" "$HP_ROOT/source"
    hp_fail 'Could not stage the replacement source.'
  fi
  hp_log "Rebuilding from $repo ($sha), preserving Docker volume ${project}_house-data"
  if hp_create_compose "$project" "$HP_PORT" && hp_compose "$project" config --quiet && hp_compose "$project" up -d --build && hp_check_http "$HP_PORT"; then
    hp_save_fingerprint
    hp_save_manifest "$HP_SOURCE" "$repo" "$sha" "$project" "$HP_PORT" installed
    hp_install_launchers "$(uname -s)"
    if [[ "$changed" == yes ]]; then
      hp_log "User-edited prior source preserved at: $old"
    elif cmp -s <(hp_fingerprint "$old") "$HP_TMP/prior-source-files.tsv"; then
      rm -rf -- "$old"
    else
      hp_log "Prior source changed during repair, retained at: $old"
    fi
    if [[ "$haveImage" == yes ]]; then docker image rm "$backupImage" >/dev/null 2>&1 || :; fi
    hp_log 'Repair completed; plans, snapshots and credentials remain in the same data volume.'
  else
    hp_log 'Rebuild failed. Restoring old source and Compose configuration.'
    # The replacement source came from the verified staging ZIP, not from user edits.
    if [[ -d "$HP_ROOT/source" && ! -L "$HP_ROOT/source" ]]; then rm -rf -- "$HP_ROOT/source"; fi
    mv "$old" "$HP_ROOT/source"
    cp "$backupCompose" "$HP_ROOT/house-planner.compose.yml"
    if [[ "$haveImage" == yes ]]; then
      if docker tag "$backupImage" "$oldImage"; then
        hp_compose "$project" up -d --no-build || hp_log 'Old image restored, but automatic container restart failed.'
      else
        hp_log 'Could not retag the previous image; previous source was still restored.'
      fi
      docker image rm "$backupImage" >/dev/null 2>&1 || :
    fi
    hp_fail 'Repair failed and previous source was restored. Docker data volume is intact.'
  fi
}
hp_remove_tracked_source() {
  local index="$HP_ROOT/.hp-source-files.tsv" dir="$HP_ROOT/source" sum path actual
  [[ -f "$index" && ! -L "$index" ]] || hp_fail 'Source ownership hashes are missing; refusing source deletion.'
  [[ ! -L "$dir" ]] || hp_fail 'Source root is a symlink; refusing to remove.'
  [[ -d "$dir" ]] || return 0
  if [[ -n "$(find "$dir" -type l -print -quit)" ]]; then
    hp_log 'Source contains symlinks; preserving the complete source folder rather than risking external deletions.'
    return 0
  fi
  while IFS=$'\t' read -r sum path; do
    [[ "$sum" =~ ^[a-f0-9]{64}$ && "$path" == ./* && "$path" != *'/../'* && "$path" != *'/./'* ]] || hp_fail 'Invalid source ownership entry.'
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]] || hp_fail 'Unsafe source path in ownership list.'
    if [[ -f "$dir/$path" && ! -L "$dir/$path" ]]; then
      actual="$(hp_sha256 "$dir/$path")"
      if [[ "$actual" == "$sum" ]]; then rm -f -- "$dir/$path"; else hp_log "Preserved modified source: $path"; fi
    fi
  done < "$index"
  # Remove only empty directories. User-added files and links remain untouched.
  while IFS= read -r child; do rmdir "$child" 2>/dev/null || :; done < <(find "$dir" -depth -type d)
  if [[ -d "$dir" ]]; then hp_log "Preserved untracked/modified files in $dir"; fi
}
hp_uninstall() {
  local project archive
  hp_validate_root "$HP_ROOT"; hp_validate_manifest
  hp_docker_check
  [[ -f "$HP_ROOT/house-planner.compose.yml" && ! -L "$HP_ROOT/house-planner.compose.yml" ]] || hp_fail 'Owned Compose file missing or linked; Repair before uninstall.'
  project="$(hp_manifest_value HP_PROJECT)"
  hp_log "Stopping only Docker Compose project $project (without -v)."
  hp_compose "$project" down || hp_fail 'Could not stop managed containers; refusing to remove local management files.'
  docker image rm "house-planner-installer-$project:local" >>"$HP_LOG" 2>&1 || hp_log 'Image may still be in use; retained rather than force-deleted.'
  hp_remove_tracked_source
  # Keep unexpected user files, including any edited source, and never remove Docker volumes.
  local file
  for file in house-planner.compose.yml .env .hp-source-files.tsv .hp-install-manifest 'Start House Planner.sh' 'Start House Planner.command' 'Install House Planner - Linux.sh' 'Install House Planner - macOS.command' HousePlanner-Unix-Core.sh; do
    if [[ -f "$HP_ROOT/$file" && ! -L "$HP_ROOT/$file" ]]; then rm -f -- "$HP_ROOT/$file"; fi
  done
  rmdir "$HP_ROOT" 2>/dev/null || hp_log 'Untracked or modified files remain in the former installation directory.'
  hp_log "SUCCESS: Uninstalled application. House plans are preserved in Docker volume ${project}_house-data."
}
hp_launch() {
  hp_validate_root "$HP_ROOT"; hp_validate_manifest; hp_docker_check
  local project port url
  project="$(hp_manifest_value HP_PROJECT)";port="$(hp_manifest_value HP_PORT)"
  [[ -f "$HP_ROOT/house-planner.compose.yml" && ! -L "$HP_ROOT/house-planner.compose.yml" ]] || hp_fail 'Missing or linked Compose file; run Repair.'
  hp_compose "$project" up -d --no-build || hp_fail 'Could not start installed container. Run Repair.'
  hp_check_http "$port" || hp_fail 'Application did not respond. Check Docker and run Repair.'
  url="http://127.0.0.1:$port/"
  hp_log "Opening browser: $url"
  if [[ "$(uname -s)" == Darwin ]]; then open "$url"; elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url"; else hp_log "Open this URL in a browser: $url"; fi
}
hp_main() {
  [[ "$HP_MODE" == Install || "$HP_MODE" == Repair || "$HP_MODE" == Uninstall || "$HP_MODE" == Launch ]] || hp_fail 'Usage: core.sh {Install|Repair|Uninstall|Launch} /absolute/path [Original|Fork] [port] [yes|no]'
  if [[ "$HP_MODE" == Install || "$HP_MODE" == Repair ]]; then
    [[ "$HP_PORT" =~ ^[0-9]+$ && "$HP_PORT" -ge 1024 && "$HP_PORT" -le 65535 ]] || hp_fail 'Port must be between 1024 and 65535.'
    [[ "$HP_SOURCE" == Original || "$HP_SOURCE" == Fork ]] || hp_fail 'Source must be Original or Fork.'
  fi
  hp_log "House Planner Dual-Repository Installer 1.0 | $HP_MODE | $HP_ROOT"
  hp_log "Diagnostic log: $HP_LOG"
  case "$HP_MODE" in
    Install) hp_install;;
    Repair) hp_repair;;
    Uninstall) hp_uninstall;;
    Launch) hp_launch;;
  esac
}
hp_main
