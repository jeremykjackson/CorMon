#!/bin/bash
# CorMon installer / updater.
#
# Pulls the latest CorMon from GitHub, builds it, and installs CorMon.app into
# /Applications (or ~/Applications if /Applications isn't writable), then relaunches it.
#
# Usage:
#   ./install.sh              update, build and install (skips the build if already current)
#   ./install.sh --force      rebuild and reinstall even if already up to date
#   ./install.sh --no-launch  don't open CorMon afterwards
#   ./install.sh --dir PATH   use/clone the source in PATH (default: this script's folder,
#                             or ~/CorMon when run from elsewhere)
#
# Requirements: macOS 13+, Xcode or the Command Line Tools (xcode-select --install),
# and GitHub access to the private repo (e.g. via `gh auth login`).

set -euo pipefail

REPO_URL="https://github.com/jeremykjackson/CorMon.git"
BRANCH="main"
APP_NAME="CorMon.app"
EXECUTABLE="SystemMonitor"
COMMIT_KEY="CorMonCommit"

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
step()  { printf '\033[33m▸\033[0m %s\n' "$*"; }
ok()    { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m!\033[0m %s\n' "$*"; }
fail()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

main() {
  local force=0 launch=1 pull=1 src_dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --force|-f)   force=1 ;;
      --no-launch)  launch=0 ;;
      --no-pull)    pull=0 ;;   # used internally after the script updates itself
      --dir)        shift; src_dir="${1:-}"; [ -n "$src_dir" ] || fail "--dir needs a path" ;;
      --help|-h)    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *)            fail "Unknown option: $1 (try --help)" ;;
    esac
    shift
  done

  bold "CorMon installer"

  # --- Prerequisites ---------------------------------------------------------
  [ "$(uname -s)" = "Darwin" ] || fail "This installer only runs on macOS."
  command -v git >/dev/null || fail "git not found. Install the Command Line Tools: xcode-select --install"
  if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null; then
    fail "Swift toolchain not found. Install the Command Line Tools: xcode-select --install"
  fi

  # --- Locate the source -----------------------------------------------------
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -z "$src_dir" ]; then
    if [ -f "$script_dir/Package.swift" ] && [ -d "$script_dir/.git" ]; then
      src_dir="$script_dir"
    else
      src_dir="$HOME/CorMon"
    fi
  fi

  if [ ! -d "$src_dir/.git" ]; then
    [ -e "$src_dir" ] && [ -n "$(ls -A "$src_dir" 2>/dev/null)" ] \
      && fail "$src_dir exists but isn't a CorMon checkout. Pass --dir with another path."
    step "Cloning CorMon into ${src_dir}…"
    git clone --branch "$BRANCH" "$REPO_URL" "$src_dir" \
      || fail "Clone failed. The repo is private. Sign in first with: gh auth login"
    pull=0
  fi
  cd "$src_dir"

  # --- Pull the latest -------------------------------------------------------
  if [ "$pull" -eq 1 ]; then
    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    [ "$current_branch" = "$BRANCH" ] \
      || fail "Source is on branch '$current_branch'. Switch back with: git -C \"$src_dir\" checkout $BRANCH"

    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      fail "You have local edits in $src_dir. Keep them with 'git stash', or discard them with 'git checkout -- .', then run again."
    fi

    step "Checking GitHub for updates…"
    git fetch --quiet origin "$BRANCH" \
      || fail "Couldn't reach GitHub. Check your connection, or sign in with: gh auth login"

    local before after self_before self_after
    before="$(git rev-parse HEAD)"
    self_before="$(git hash-object "$script_dir/install.sh" 2>/dev/null || true)"
    git merge --ff-only --quiet "origin/$BRANCH" \
      || fail "Couldn't fast-forward to the latest version. Your local history has diverged from GitHub."
    after="$(git rev-parse HEAD)"

    if [ "$before" != "$after" ]; then
      ok "Pulled $(git rev-list --count "$before..$after") new commit(s):"
      git log --format='    %h %s' "$before..$after"
    else
      ok "Source is already at the latest commit."
    fi

    # If this script was just updated, hand over to the new version.
    if [ "$script_dir" = "$src_dir" ]; then
      self_after="$(git hash-object install.sh)"
      if [ -n "$self_before" ] && [ "$self_before" != "$self_after" ]; then
        step "The installer itself was updated; restarting it…"
        local args=(--no-pull --dir "$src_dir")
        [ "$force" -eq 1 ] && args+=(--force)
        [ "$launch" -eq 0 ] && args+=(--no-launch)
        exec bash "$src_dir/install.sh" "${args[@]}"
      fi
    fi
  fi

  local commit version
  commit="$(git rev-parse HEAD)"
  version="$(plist_get Resources/Info.plist CFBundleShortVersionString)"

  # --- Where to install ------------------------------------------------------
  local dest_dir="/Applications"
  if [ ! -w "$dest_dir" ]; then
    dest_dir="$HOME/Applications"
    mkdir -p "$dest_dir"
  fi
  local dest="$dest_dir/$APP_NAME"

  # Already installed from this exact commit?
  if [ "$force" -eq 0 ] && [ -d "$dest" ]; then
    local installed_commit
    installed_commit="$(plist_get "$dest/Contents/Info.plist" "$COMMIT_KEY")"
    if [ "$installed_commit" = "$commit" ]; then
      ok "CorMon ${version} (${commit:0:7}) is already installed and up to date."
      echo "  Run with --force to rebuild anyway."
      if [ "$launch" -eq 1 ] && ! pgrep -x "$EXECUTABLE" >/dev/null; then
        open "$dest"
      fi
      exit 0
    fi
  fi

  # --- Build -----------------------------------------------------------------
  step "Building CorMon ${version} (${commit:0:7})… this can take a minute."
  ./build.sh || fail "Build failed. Copy the errors above and send them over."

  local built="build/$APP_NAME"
  [ -d "$built" ] || fail "Build finished but $built is missing."

  # Stamp the commit into the app so the next run can tell if it's current, then re-sign.
  /usr/libexec/PlistBuddy -c "Delete :$COMMIT_KEY" "$built/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$COMMIT_KEY string $commit" "$built/Contents/Info.plist"
  codesign --force --deep --sign - "$built" >/dev/null

  # --- Quit the running copy -------------------------------------------------
  if pgrep -x "$EXECUTABLE" >/dev/null; then
    step "Quitting the running CorMon…"
    osascript -e 'tell application id "com.jeremyjackson.SystemMonitor" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -x "$EXECUTABLE" >/dev/null || break
      sleep 0.5
    done
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    sleep 0.5
  fi

  # --- Install ---------------------------------------------------------------
  local old_version=""
  [ -d "$dest" ] && old_version="$(plist_get "$dest/Contents/Info.plist" CFBundleShortVersionString)"

  step "Installing to ${dest}…"
  rm -rf "$dest"
  ditto "$built" "$dest"
  # Refresh Launch Services so Finder, Spotlight and the Dock pick up the new icon/version.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$dest" >/dev/null 2>&1 || true

  if [ -n "$old_version" ] && [ "$old_version" != "$version" ]; then
    ok "Updated CorMon ${old_version} → ${version} (${commit:0:7})."
  else
    ok "Installed CorMon ${version} (${commit:0:7})."
  fi

  if [ -d "/Applications/System Monitor.app" ]; then
    warn "The old v1 app is still at /Applications/System Monitor.app. You can delete it."
  fi

  # --- Launch ----------------------------------------------------------------
  if [ "$launch" -eq 1 ]; then
    open "$dest"
    ok "CorMon is running."
  fi
}

# Everything runs from main(), so bash has read the whole file before `git pull` can change it.
main "$@"
exit $?
