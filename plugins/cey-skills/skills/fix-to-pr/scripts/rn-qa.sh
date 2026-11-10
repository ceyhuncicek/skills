#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2016  # ls on our own cache paths; node -e scripts are single-quoted on purpose
# rn-qa.sh: build, install, launch and serve a React Native app for agent QA.
# Works for Expo (CNG or committed native dirs) and bare React Native, on macOS.
# Every wait has a timeout; nothing prompts. Run from the project root (or set
# RN_QA_PROJECT). Usage: rn-qa.sh help
#
# State:  ${RN_QA_HOME:-~/.cache/rn-qa}/<project-slug>/<worktree>/   (kv/, logs)
# Cache:  ${RN_QA_HOME}/<project-slug>/cache/<platform>-<fingerprint>/   (shared by worktrees)
# Global: ${RN_QA_HOME}/build.lock (one native build per machine). Metro runs per worktree
# on 8081, else the first free port 8082-8099 (or --port N / RN_QA_PORT).

SELF="$0"
case "$SELF" in /*) ;; *) SELF="$(cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF")" ;; esac
RN_QA_HOME="${RN_QA_HOME:-$HOME/.cache/rn-qa}"
POLL=5

die() { echo "rn-qa: ERROR: $*" >&2; exit 1; }
say() { echo "rn-qa: $*"; }
now() { date +%s; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }

# run_timeout SECS CMD...  (macOS has no timeout(1)); returns 124 on timeout
run_timeout() {
  local secs=$1; shift
  "$@" & local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 5; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local w=$!
  wait "$pid"; local rc=$?
  if alive "$w"; then kill "$w" 2>/dev/null; wait "$w" 2>/dev/null; else rc=124; fi
  return $rc
}

# ---------- project + state ----------
find_project() {
  local d="${RN_QA_PROJECT:-$PWD}"
  while [ "$d" != "/" ]; do [ -f "$d/package.json" ] && { echo "$d"; return; }; d=$(dirname "$d"); done
  die "no package.json found above ${RN_QA_PROJECT:-$PWD}"
}
PROJ=$(find_project) || exit 1
hash8() { printf %s "$1" | shasum | cut -c1-8; }
common=$(cd "$PROJ" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -n "$common" ]; then root=$(dirname "$common"); else root="$PROJ"; fi
SLUG="$(basename "$root")-$(hash8 "$root")"
BASE="$RN_QA_HOME/$SLUG"
STATE="$BASE/$(basename "$PROJ")-$(hash8 "$PROJ")"
CACHE="$BASE/cache"
mkdir -p "$STATE/kv" "$CACHE" || die "cannot create $STATE"

sset() { printf %s "$2" > "$STATE/kv/$1.tmp" && mv "$STATE/kv/$1.tmp" "$STATE/kv/$1"; }
sget() { cat "$STATE/kv/$1" 2>/dev/null; }
gset() { printf %s "$2" > "$RN_QA_HOME/$1"; }
gget() { cat "$RN_QA_HOME/$1" 2>/dev/null; }

# jget FILE DOTTED.PATH -> value (objects as JSON); empty if missing
jget() {
  [ -f "$1" ] || return 0
  node -e 'let o;try{o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))}catch(e){process.exit(0)}
for(const k of process.argv[2].split(".").filter(Boolean))o=o==null?undefined:o[k];
if(o!=null)console.log(typeof o==="object"?JSON.stringify(o):String(o))' "$1" "$2"
}
QA_CFG="$PROJ/.claude/mobile-qa.json"
cfg() { jget "$QA_CFG" "$1"; }

# "skip": {"<platform>": "reason"} in mobile-qa.json parks a platform: build/install/launch
# print SKIPPED and exit 3. --no-skip or RN_QA_NO_SKIP=1 ignores it (to verify that platform).
NO_SKIP="${RN_QA_NO_SKIP:-0}"
FORCE_PARALLEL="${RN_QA_FORCE_PARALLEL:-0}"
skip_reason() { cfg "skip.$1"; }
check_skip() {
  [ "$NO_SKIP" = 1 ] && return 0
  local r; r=$(skip_reason "$1"); [ -n "$r" ] || return 0
  echo "SKIPPED: $1 — $r (set in .claude/mobile-qa.json)"; exit 3
}

# export env overrides from mobile-qa.json "env"
if [ -f "$QA_CFG" ]; then
  while IFS= read -r kv; do [ -n "$kv" ] && export "${kv?}"; done < <(node -e '
try{const e=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).env||{};
for(const[k,v]of Object.entries(e))console.log(k+"="+v)}catch(e){}' "$QA_CFG")
fi

has_dep() { node -e 'const p=require(process.argv[1]);const d={...p.dependencies,...p.devDependencies};process.exit(d[process.argv[2]]?0:1)' "$PROJ/package.json" "$1"; }
IS_EXPO=0; has_dep expo && IS_EXPO=1
project_type() {  # bare | expo-cng (native dirs generated, gitignored) | expo-native (committed)
  [ $IS_EXPO = 0 ] && { echo bare; return; }
  if [ ! -d "$PROJ/ios" ] && [ ! -d "$PROJ/android" ]; then echo expo-cng; return; fi
  if (cd "$PROJ" && { git check-ignore -q ios || git check-ignore -q android; } 2>/dev/null); then echo expo-cng; else echo expo-native; fi
}
bin() { [ -x "$PROJ/node_modules/.bin/$1" ] && echo "$PROJ/node_modules/.bin/$1"; }
need_modules() { [ -d "$PROJ/node_modules" ] || die "node_modules missing in $PROJ: run the repo's install (npm ci / yarn) first"; }
check_plat() { case "$1" in ios|android) ;; *) die "platform must be ios or android, got '${1:-}'" ;; esac; }
free_gb() { df -Pk "$PROJ" | awk 'NR==2{print int($4/1048576)}'; }

# ---------- app ids ----------
expo_config() {  # path of the cached public expo config (keyed by APP_*/EXPO_* env)
  [ $IS_EXPO = 1 ] && [ -n "$(bin expo)" ] || return 1
  local f; f="$STATE/expo-config-$(hash8 "$(env | grep -E '^(APP|EXPO)_' | sort)").json"
  if [ ! -s "$f" ] || [ -n "$(find "$PROJ/app.json" "$PROJ"/app.config.* "$QA_CFG" -newer "$f" 2>/dev/null)" ]; then
    (cd "$PROJ" && run_timeout 90 "$(bin expo)" config --json --type public >"$f.tmp" 2>/dev/null) && [ -s "$f.tmp" ] && mv "$f.tmp" "$f"
    rm -f "$f.tmp"
  fi
  [ -s "$f" ] && echo "$f"
}
app_id() {  # app_id ios|android
  local v="" ec
  if [ "$1" = ios ]; then v=$(cfg ios.bundleId); else v=$(cfg android.package); fi
  if [ -z "$v" ] && [ $IS_EXPO = 1 ] && ec=$(expo_config); then
    if [ "$1" = ios ]; then v=$(jget "$ec" ios.bundleIdentifier); else v=$(jget "$ec" android.package); fi
  fi
  if [ -z "$v" ] && [ "$1" = ios ]; then
    v=$(grep -h -m1 'PRODUCT_BUNDLE_IDENTIFIER' "$PROJ"/ios/*.xcodeproj/project.pbxproj 2>/dev/null | head -1 | sed -E 's/.*= *"?([^";]+)"?;.*/\1/')
  elif [ -z "$v" ]; then
    v=$(grep -h -m1 -E 'applicationId' "$PROJ"/android/app/build.gradle* 2>/dev/null | head -1 | sed -E "s/.*[\"']([^\"']+)[\"'].*/\1/")
  fi
  echo "$v"
}
artifact_id() {  # id read from the built artifact itself (most reliable)
  local a; a=$(sget "artifact_$1")
  [ -e "$a" ] || return 0
  if [ "$1" = ios ]; then /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$a/Info.plist" 2>/dev/null
  else
    local aapt; aapt=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt 2>/dev/null | tail -1)
    [ -n "$aapt" ] && "$aapt" dump badging "$a" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p"
  fi
}
resolved_id() { local v; v=$(artifact_id "$1"); [ -n "$v" ] || v=$(app_id "$1"); [ -n "$v" ] || die "cannot resolve $1 app id; set it in .claude/mobile-qa.json"; echo "$v"; }

# ---------- fingerprint ----------
fingerprint() {
  local p=$1 out
  check_plat "$p"; need_modules
  if [ -n "$(bin expo-updates)" ]; then
    out=$(cd "$PROJ" && run_timeout 120 "$(bin expo-updates)" fingerprint:generate --platform "$p" 2>/dev/null)
  elif [ -n "$(bin fingerprint)" ]; then
    out=$(cd "$PROJ" && run_timeout 120 "$(bin fingerprint)" fingerprint:generate --platform "$p" 2>/dev/null)
  fi
  local h; h=$(printf %s "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).hash)}catch(e){}})' 2>/dev/null)
  if [ -z "$h" ]; then  # bare RN fallback
    h=$( { cd "$PROJ" && cat package.json package-lock.json yarn.lock pnpm-lock.yaml app.json 2>/dev/null
           if [ "$p" = ios ]; then cat ios/Podfile ios/Podfile.lock ios/*.xcodeproj/project.pbxproj 2>/dev/null
           else cat android/build.gradle android/app/build.gradle android/gradle.properties android/settings.gradle 2>/dev/null; fi
           env | grep -E '^(APP_VARIANT|NODE_ENV)=' ; } | shasum | cut -c1-40)
    h="raw-$h"
  fi
  echo "$h"
}
cached_artifact() {  # cached_artifact PLAT FP
  local d="$CACHE/$1-$2"
  if [ "$1" = ios ]; then ls -d "$d"/*.app 2>/dev/null | head -1; else ls "$d"/*.apk 2>/dev/null | head -1; fi
}

# ---------- build lock (one native build per machine) ----------
LOCK="$RN_QA_HOME/build.lock"
lock_holder() { local p; p=$(cat "$LOCK/pid" 2>/dev/null); alive "$p" && echo "$p $(cat "$LOCK/info" 2>/dev/null)"; }
lock_take() {
  if mkdir "$LOCK" 2>/dev/null || { [ -z "$(lock_holder)" ] && rm -rf "$LOCK" && mkdir "$LOCK" 2>/dev/null; }; then
    echo $$ > "$LOCK/pid"; echo "$1 $PROJ" > "$LOCK/info"; return 0
  fi
  return 1
}
lock_drop() { [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK"; }

# ---------- build ----------
build_inner() {  # runs with stdout/stderr already going to the build log
  local p=$1 fp art rc marker out
  trap 'lock_drop; [ "$(sget build_status)" = running ] && sset build_status failed' EXIT
  lock_take "$p" || { sset build_status failed; echo "another rn-qa build holds the lock: $(lock_holder)"; return 1; }
  sset build_status running; sset build_pid $$; sset build_platform "$p"; sset build_started "$(now)"
  echo "== rn-qa build $p in $PROJ ($(project_type)) at $(date)"
  [ "$(free_gb)" -lt 5 ] && { echo "only $(free_gb) GB free; refusing to build"; sset build_status failed; return 1; }
  fp=$(fingerprint "$p") || { sset build_status failed; return 1; }
  sset "fingerprint_$p" "$fp"; echo "fingerprint $p: $fp"
  art=$(cached_artifact "$p" "$fp")
  if [ -n "$art" ]; then
    echo "cache hit: $art"; sset "artifact_$p" "$art"; sset build_status cached; sset build_ended "$(now)"; return 0
  fi
  marker="$STATE/build-$p.marker"; touch "$marker"; out="$STATE/out-$p"; rm -rf "$out"; mkdir -p "$out"
  cd "$PROJ" || return 1
  if [ "$p" = ios ]; then
    if [ $IS_EXPO = 1 ]; then
      local scheme; scheme=$(cfg ios.scheme)
      # No RCT_METRO_PORT: Info.plist RCTMetroPort stays empty, so launch can pick the port via RCT_jsLocation.
      env -u RCT_METRO_PORT CI=1 "$(bin expo)" run:ios --no-bundler --device generic --configuration Debug --output "$out" ${scheme:+--scheme "$scheme"}
      rc=$?
      art=$(find "$out" -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -1)
      if [ -z "$art" ]; then  # fall back to the .app path named in the build log
        art=$(grep -oE '/[^ "]*Debug-iphonesimulator/[^ "/]+\.app' "$STATE/build-$p.log" | tail -1)
        [ -n "$art" ] && [ -z "$(find "$art" -maxdepth 0 -newer "$marker" 2>/dev/null)" ] && art=""
      fi
    else
      [ -d ios/Pods ] || (cd ios && run_timeout 900 pod install) || { sset build_status failed; return 1; }
      local ws scheme; ws=$(ls -d ios/*.xcworkspace | head -1); scheme=$(cfg ios.scheme); [ -n "$scheme" ] || scheme=$(basename "$ws" .xcworkspace)
      env -u RCT_METRO_PORT xcodebuild -workspace "$ws" -scheme "$scheme" -configuration Debug -sdk iphonesimulator \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$STATE/dd" build
      rc=$?
      art=$(find "$STATE/dd/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' -newer "$marker" 2>/dev/null | head -1)
    fi
  else
    if [ $IS_EXPO = 1 ] && [ ! -d android ]; then
      CI=1 "$(bin expo)" prebuild --platform android --no-install || { sset build_status failed; return 1; }
    fi
    (cd android && ./gradlew --console=plain :app:assembleDebug); rc=$?
    art=$(find android/app/build/outputs/apk/debug -name '*.apk' -newer "$marker" 2>/dev/null | head -1)
  fi
  if [ -z "$art" ]; then
    echo "build failed (exit $rc), no artifact found"; sset build_status failed; sset build_ended "$(now)"; return 1
  fi
  [ "$rc" != 0 ] && echo "build command exited $rc but the artifact exists (e.g. the osascript Simulator error): treating as success"
  local dest="$CACHE/$p-$fp"; rm -rf "$dest.tmp"; mkdir -p "$dest.tmp" && cp -R "$art" "$dest.tmp/" && rm -rf "$dest" && mv "$dest.tmp" "$dest"
  rm -rf "$out"
  ls -dt "$CACHE/$p"-* 2>/dev/null | tail -n +4 | while read -r old; do rm -rf "$old"; done  # keep 3 per platform
  art=$(cached_artifact "$p" "$fp"); echo "artifact: $art"
  sset "artifact_$p" "$art"; sset build_status "done"; sset build_ended "$(now)"
}
cmd_build() {
  local p="" detach=0 child=0 a
  for a in "$@"; do case "$a" in --detach) detach=1 ;; --_child) child=1 ;; *) p=$a ;; esac; done
  check_plat "$p"; [ $child = 1 ] || { check_skip "$p"; check_parallel "$p"; }; need_modules
  local log="$STATE/build-$p.log"
  if [ $child = 1 ]; then build_inner "$p" >> "$log" 2>&1; return $?; fi
  local h; h=$(lock_holder); [ -n "$h" ] && die "a native build is already running (pid/platform/project): $h. Use 'rn-qa.sh wait build' or wait for it."
  : > "$log"; sset build_status starting; sset build_platform "$p"; sset build_log "$log"; sset build_started "$(now)"
  rm -f "$STATE/kv/build_ended" "$STATE/kv/build_pid"
  if [ $detach = 1 ]; then
    nohup "$BASH" "$SELF" build "$p" --_child </dev/null >/dev/null 2>&1 &
    sset build_pid $!
    say "build $p started detached: pid $! log $log"
    say "next: rn-qa.sh wait build   (repeat while it exits 2)"
    return 0
  fi
  say "building $p, log $log"
  "$BASH" "$SELF" build "$p" --_child; local rc=$?
  tail -n 15 "$log"; return $rc
}

# ---------- devices ----------
ios_booted() { xcrun simctl list devices booted 2>/dev/null | sed -nE 's/^ +(.+) \(([0-9A-F-]{36})\) \(Booted\).*/\2 \1/p'; }
ios_udid() {  # pick (and boot if needed) a simulator; prints UDID
  local u want; u=$(sget ios_udid); want=$(cfg ios.device)
  if [ -n "$u" ] && ios_booted | grep -q "^$u "; then echo "$u"; return; fi
  if [ -n "$want" ]; then u=$(ios_booted | grep -E "^$want | $want\$" | head -1 | cut -d' ' -f1); else u=$(ios_booted | head -1 | cut -d' ' -f1); fi
  if [ -z "$u" ]; then
    if [ -n "$want" ]; then u=$(xcrun simctl list devices available | grep -F "$want" | grep -oE '[0-9A-F-]{36}' | head -1)
    else u=$(xcrun simctl list devices available | grep -E '^ +iPhone' | grep -oE '[0-9A-F-]{36}' | head -1); fi
    [ -n "$u" ] || die "no iOS simulator available"
    say "booting simulator $u" >&2
    xcrun simctl boot "$u" >/dev/null 2>&1; sset ios_booted_by_rnqa "$u"
    run_timeout 240 xcrun simctl bootstatus "$u" -b >/dev/null 2>&1 || die "simulator $u did not boot in 240 s"
  fi
  sset ios_udid "$u"; echo "$u"
}
ADB="adb"; command -v adb >/dev/null 2>&1 || ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
EMU="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"
adb_devices() { "$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}'; }
android_serial() {
  local s; s=$(sget android_serial)
  if [ -n "$s" ] && adb_devices | grep -qx "$s"; then echo "$s"; return; fi
  s=$(adb_devices | head -1)
  if [ -z "$s" ]; then
    local avd; avd=$(cfg android.avd); [ -n "$avd" ] || avd=$("$EMU" -list-avds 2>/dev/null | head -1)
    [ -n "$avd" ] || die "no Android device connected and no AVD found"
    say "starting emulator $avd" >&2
    nohup "$EMU" -avd "$avd" -no-boot-anim </dev/null >"$STATE/emulator.log" 2>&1 &
    sset emulator_pid $!
    local t0; t0=$(now)
    while [ $(( $(now) - t0 )) -lt 300 ]; do
      s=$(adb_devices | head -1)
      [ -n "$s" ] && [ "$("$ADB" -s "$s" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
      s=""; sleep $POLL
    done
    [ -n "$s" ] || die "emulator did not boot in 300 s (log $STATE/emulator.log)"
  fi
  sset android_serial "$s"; echo "$s"
}

# check_parallel PLAT: exit 4 while the other platform is still active (one platform at a time).
check_parallel() {
  [ "$FORCE_PARALLEL" = 1 ] && return 0
  local o=ios why="" h u; [ "$1" = ios ] && o=android
  [ "$(sget active_platform)" = "$o" ] && [ -n "$(my_port)" ] && why="this worktree's Metro is up with $o launched"
  h=$(lock_holder); [ -n "$h" ] && [ "$(echo "$h" | cut -d' ' -f2)" = "$o" ] && why="a $o build holds the lock ($h)"
  if [ "$o" = ios ]; then u=$(sget ios_booted_by_rnqa); [ -n "$u" ] && ios_booted | grep -q "^$u " && why="the iOS simulator rn-qa booted ($u) is still running"
  else alive "$(sget emulator_pid)" && why="the Android emulator rn-qa started (pid $(sget emulator_pid)) is still running"; fi
  [ -n "$why" ] || return 0
  echo "REFUSED: $1 while $o is active: $why. Finish $o first: close its agent-device session, run 'rn-qa.sh cleanup' (add --shutdown if rn-qa booted the device). --force-parallel overrides."
  exit 4
}

cmd_install() {
  local p=$1 art; check_plat "$p"; check_skip "$p"; check_parallel "$p"; art=$(sget "artifact_$p")
  [ -e "$art" ] || die "no built artifact for $p; run: rn-qa.sh build $p --detach && rn-qa.sh wait build"
  [ "$(sget build_status)" = running ] && die "a build is running; wait for it first"
  if [ "$p" = ios ]; then
    local u; u=$(ios_udid) || exit 1
    run_timeout 180 xcrun simctl install "$u" "$art" || die "simctl install failed"
    say "installed $(basename "$art") on simulator $u"
  else
    local s o; s=$(android_serial) || exit 1
    o=$(run_timeout 300 "$ADB" -s "$s" install -r -d "$art" 2>&1); echo "$o" | tail -3
    echo "$o" | grep -q Success || {
      echo "$o" | grep -q INSTALL_FAILED_UPDATE_INCOMPATIBLE && say "signature mismatch: 'adb -s $s uninstall $(resolved_id android)' wipes app data; ask before doing it"
      die "adb install failed"; }
    say "installed $(basename "$art") on $s"
  fi
  sset "installed_$p" "$(sget "fingerprint_$p")"; sset active_platform "$p"
}

# ---------- metro (one per worktree, own port) ----------
# The app always asks for 8081 on Android (adb reverse maps it to our port). iOS debug
# builds read NSUserDefaults RCT_jsLocation (RCTBundleURLProvider), set per launch.
port_pid() { lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1; }
pid_cwd() { lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; }
metro_up() { [ "$(curl -s --max-time 3 "http://localhost:$1/status")" = "packager-status:running" ]; }
metro_listeners() {  # "port pid cwd" for every listener on 8081-8099
  lsof -nP -iTCP:8081-8099 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{split($9,a,":"); print a[length(a)], $2}' | sort -u |
    while read -r port pid; do echo "$port $pid $(pid_cwd "$pid")"; done
}
my_port() {  # port of this worktree's running Metro, empty if none
  local p; p=$(sget metro_port)
  [ -n "$p" ] && metro_up "$p" && [ "$(pid_cwd "$(port_pid "$p")")" = "$PROJ" ] && echo "$p"
}
need_metro() { MPORT=$(my_port); [ -n "$MPORT" ] || die "no Metro running for this worktree; run: rn-qa.sh metro start"; }
adb_reverse() {  # device 8081 -> host port $1
  local s; for s in $(adb_devices); do "$ADB" -s "$s" reverse tcp:8081 tcp:"$1" >/dev/null 2>&1; done
}
adb_unreverse() {  # remove device 8081 only if it points at our port
  local s; for s in $(adb_devices); do
    "$ADB" -s "$s" reverse --list 2>/dev/null | grep -q "tcp:8081 tcp:$1\$" && "$ADB" -s "$s" reverse --remove tcp:8081 >/dev/null 2>&1
  done
}
kill_tree() { local p; for p in "$@"; do alive "$p" || continue; pkill -TERM -P "$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; done
  local i=0; while [ $i -lt 10 ]; do local any=0; for p in "$@"; do alive "$p" && any=1; done; [ $any = 0 ] && return 0; sleep 1; i=$((i+1)); done
  for p in "$@"; do kill -KILL "$p" 2>/dev/null; done; }
cmd_metro() {
  local action=${1:-} force=0 want="${RN_QA_PORT:-}"; [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do case "$1" in --force) force=1 ;; --port) want=$2; shift ;; esac; shift; done
  case "$action" in
    status)
      local p; p=$(my_port)
      if [ -n "$p" ]; then say "this worktree's Metro: port $p pid $(port_pid "$p") running"; else say "this worktree's Metro: stopped"; fi
      metro_listeners | while read -r port pid cwd; do echo "  port $port: pid $pid cwd $cwd"; done ;;
    stop)
      if [ $force = 1 ]; then  # kill a foreign Metro; only when its worktree has no live QA session
        local fp="${want:-8081}" o; o=$(port_pid "$fp")
        if [ -n "$o" ] && [ "$(pid_cwd "$o")" != "$PROJ" ]; then say "killing foreign Metro on $fp: pid $o ($(pid_cwd "$o"))"; kill_tree "$o"; fi
      fi
      local mp port; mp=$(sget metro_pid); port=$(sget metro_port)
      if [ -n "$port" ]; then
        local l; l=$(port_pid "$port"); [ -n "$l" ] && [ "$(pid_cwd "$l")" != "$PROJ" ] && l=""
        kill_tree "$mp" "$l"; adb_unreverse "$port"; say "stopped Metro (port $port)"
      fi
      rm -f "$STATE/kv/metro_pid" "$STATE/kv/metro_port" ;;
    start)
      local p; p=$(my_port)
      if [ -n "$p" ]; then say "Metro already running for this worktree on port $p"; adb_reverse "$p"; return 0; fi
      need_modules
      if [ -n "$want" ]; then
        local o; o=$(port_pid "$want")
        [ -z "$o" ] || die "port $want is used by pid $o (cwd $(pid_cwd "$o")); pick another --port"
        p=$want
      else
        p=""; local c=8081
        while [ $c -le 8099 ]; do [ -z "$(port_pid "$c")" ] && { p=$c; break; }; c=$((c+1)); done
        [ -n "$p" ] || die "ports 8081-8099 are all in use (see rn-qa.sh metro status)"
      fi
      local log="$STATE/metro.log"
      if [ $IS_EXPO = 1 ]; then
        (cd "$PROJ" || exit 1; CI=1 nohup "$(bin expo)" start --port "$p" --localhost </dev/null >"$log" 2>&1 & echo $! > "$STATE/kv/metro_pid")
      else
        (cd "$PROJ" || exit 1; CI=1 nohup npx react-native start --port "$p" </dev/null >"$log" 2>&1 & echo $! > "$STATE/kv/metro_pid")
      fi
      sset metro_port "$p"
      say "Metro starting on port $p (pid $(sget metro_pid), log $log)"
      cmd_wait metro --timeout 90 || return $?
      adb_reverse "$p" ;;
    *) die "usage: rn-qa.sh metro start|stop|status [--port N] [--force]" ;;
  esac
}

# ---------- launch ----------
prewarm() {  # same query RN builds (RCTBundleURLProvider.mm / DevServerHelper.kt, Fusebox on), so Metro reuses the graph
  local entry="index.bundle"; [ $IS_EXPO = 1 ] && entry=".expo/.virtual-metro-entry.bundle"
  local q="platform=$1&dev=true&lazy=true&minify=false&inlineSourceMap=false&modulesOnly=false&runModule=true&excludeSource=true&sourcePaths=url-server&app=$2"
  [ "$1" = android ] && q="platform=android&dev=true&lazy=true&minify=false&app=$2&modulesOnly=false&runModule=true&excludeSource=true&sourcePaths=url-server"
  say "pre-warming $1 JS bundle on port $MPORT (up to 300 s)"
  curl -s -o /dev/null --max-time 300 "http://localhost:$MPORT/$entry?$q" || say "pre-warm did not finish; continuing"
}
bundled_count() { grep -c 'Bundled' "$STATE/metro.log" 2>/dev/null || true; }
cmd_launch() {
  local p=$1 id; check_plat "$p"; check_skip "$p"; check_parallel "$p"; id=$(resolved_id "$p") || exit 1
  sset active_platform "$p"
  need_metro
  [ "${2:-}" = --no-prewarm ] || prewarm "$p" "$id"
  local before; before=$(bundled_count)
  if [ "$p" = ios ]; then
    local u baked; u=$(ios_udid) || exit 1
    # Expo debug builds copy Info.plist RCTMetroPort into jsLocation at startup; a baked port wins.
    baked=$(/usr/libexec/PlistBuddy -c 'Print RCTMetroPort' "$(sget artifact_ios)/Info.plist" 2>/dev/null)
    [ -n "$baked" ] && [ "$baked" != "$MPORT" ] && say "WARNING: the build has RCTMetroPort=$baked baked in and will ignore port $MPORT; rebuild with rn-qa.sh build ios"
    # Launch argument = NSArgumentDomain (wins on read); the persisted default covers relaunches
    # that don't pass it (agent-device open, a tap on the icon).
    xcrun simctl spawn "$u" defaults write "$id" RCT_jsLocation "localhost:$MPORT" || die "could not set RCT_jsLocation"
    sset ios_jslocation_app "$id"
    run_timeout 60 xcrun simctl launch --terminate-running-process "$u" "$id" -RCT_jsLocation "localhost:$MPORT" >/dev/null || die "simctl launch $id failed"
  else
    local s; s=$(android_serial) || exit 1; adb_reverse "$MPORT"
    run_timeout 30 "$ADB" -s "$s" shell monkey -p "$id" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  fi
  if ! cmd_wait app "$p" --timeout 30; then
    [ "$p" = android ] || die "$id did not start on ios"
    # another app (Play Store, Gmail) may hold focus: retry once
    run_timeout 30 "$ADB" -s "$(sget android_serial)" shell monkey -p "$id" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    cmd_wait app "$p" --timeout 20 || die "$id did not reach the foreground on android"
  fi
  say "$id is running on $p, Metro port $MPORT"
  local t0; t0=$(now)  # the app is only usable once Metro has served it a bundle
  while [ $(( $(now) - t0 )) -lt 90 ]; do
    [ "$(bundled_count)" -gt "${before:-0}" ] && { say "JS bundle served: $(grep 'Bundled' "$STATE/metro.log" | tail -1)"; return 0; }
    sleep 2
  done
  say "WARNING: Metro served no new bundle within 90 s; the app may still be bundling or pointing at another Metro (log $STATE/metro.log)"
}
app_running() {  # app_running PLAT ID
  if [ "$1" = ios ]; then
    xcrun simctl spawn "$(sget ios_udid)" launchctl list 2>/dev/null | grep -q "UIKitApplication:$2"
  else
    run_timeout 15 "$ADB" -s "$(sget android_serial)" shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | grep -q "$2"
  fi
}

# ---------- wait ----------
cmd_wait() {
  local what=$1 plat="" timeout=100 a; shift  # 100 s fits the default 120 s Bash tool timeout
  while [ $# -gt 0 ]; do case "$1" in --timeout) timeout=$2; shift ;; ios|android) plat=$1 ;; esac; shift; done
  local t0; t0=$(now)
  while :; do
    case "$what" in
      build)
        local st pid; st=$(sget build_status); pid=$(sget build_pid)
        case "$st" in
          done|cached) local e; e=$(sget build_ended); [ -n "$e" ] || e=$(now)
                     say "build $(sget build_platform) $st in $(( e - $(sget build_started) )) s: $(sget "artifact_$(sget build_platform)")"; return 0 ;;
          failed|"") say "build ${st:-not started}"; [ -f "$(sget build_log)" ] && tail -n 40 "$(sget build_log)"; return 1 ;;
          *) # running/starting: make sure the builder is still alive (grace period while it starts)
             if ! alive "$pid" && [ $(( $(now) - $(sget build_started) )) -gt 30 ]; then
               sleep 1; st=$(sget build_status)
               if [ "$st" != "done" ] && [ "$st" != cached ]; then
                 sset build_status failed; say "build process ${pid:-?} died"; tail -n 40 "$(sget build_log)"; return 1
               fi; continue
             fi ;;
        esac ;;
      metro) local mport; mport=$(sget metro_port)
             [ -n "$mport" ] || { say "no Metro started for this worktree"; return 1; }
             metro_up "$mport" && { say "Metro running on port $mport"; return 0; }
             if ! alive "$(sget metro_pid)" && [ -z "$(port_pid "$mport")" ]; then
               say "Metro exited"; tail -n 40 "$STATE/metro.log"; return 1; fi ;;
      app) check_plat "$plat"; app_running "$plat" "$(resolved_id "$plat")" && return 0 ;;
      *) die "usage: rn-qa.sh wait build|metro|app [ios|android] [--timeout S]" ;;
    esac
    if [ $(( $(now) - t0 )) -ge "$timeout" ]; then
      say "still waiting for $what after $timeout s (exit 2: call wait again)"
      [ "$what" = build ] && tail -n 3 "$(sget build_log)" 2>/dev/null
      [ "$what" = app ] && return 1
      return 2
    fi
    sleep $POLL
  done
}

# ---------- status / doctor / cleanup ----------
cmd_status() {
  echo "project=$PROJ"; echo "state_dir=$STATE"
  local st; st=$(sget build_status)
  if [ -n "$st" ]; then
    local end; end=$(sget build_ended); [ -n "$end" ] || end=$(now)
    echo "build=$st platform=$(sget build_platform) pid=$(sget build_pid) alive=$(alive "$(sget build_pid)" && echo yes || echo no) elapsed=$(( end - $(sget build_started) ))s log=$(sget build_log)"
    echo "build_last_line=$(tail -n 1 "$(sget build_log)" 2>/dev/null | cut -c1-200)"
  else echo "build=none"; fi
  local p; for p in ios android; do
    [ -n "$(sget "artifact_$p")" ] && echo "$p: fingerprint=$(sget "fingerprint_$p") artifact=$(sget "artifact_$p") installed_fingerprint=$(sget "installed_$p")"
  done
  echo "lock=$(lock_holder || true)"
  local mp; mp=$(my_port); echo "metro=$( [ -n "$mp" ] && echo "port $mp pid $(port_pid "$mp") running" || echo stopped) log=$STATE/metro.log"
  echo "ios_udid=$(sget ios_udid) android_serial=$(sget android_serial)"
}
agent_sessions() {  # stale agent-device sessions + device claims
  local d="$HOME/.agent-device"; [ -d "$d" ] || return 0
  local f; for f in "$d"/device-claims/*.json; do [ -f "$f" ] || continue
    node -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));let a=false;try{process.kill(c.ownerPid,0);a=true}catch(e){}
console.log(`claim: session=${c.session} device=${c.device&&c.device.name} workspace=${c.workspace} ownerAlive=${a}`)' "$f" 2>/dev/null
  done
  local s; for s in "$d"/sessions/*/; do [ -f "$s/events.ndjson" ] || continue
    tail -n 2 "$s/events.ndjson" | grep -q '"command":"close"' && continue
    echo "open session: $(basename "$s") (last activity $(date -r "$s/events.ndjson" '+%Y-%m-%d %H:%M'))"
  done
}
cmd_doctor() {
  echo "project: $PROJ"; echo "type: $(project_type)"; echo "state dir: $STATE"; echo "cache dir: $CACHE"
  echo "mobile-qa.json: $( [ -f "$QA_CFG" ] && echo "$QA_CFG" || echo none)"
  [ -f "$QA_CFG" ] && echo "env overrides: $(node -e 'try{console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1])).env||{}).join(" ")||"none")}catch(e){console.log("invalid JSON")}' "$QA_CFG")"
  [ -f "$QA_CFG" ] && node -e 'try{const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).skip||{};
for(const[k,v]of Object.entries(s))if(v)console.log("skip: "+k+" ("+v+")"+(process.argv[2]==="1"?" [ignored: --no-skip]":""))}catch(e){}' "$QA_CFG" "$NO_SKIP"
  echo "node_modules: $( [ -d "$PROJ/node_modules" ] && echo present || echo 'MISSING (install deps first)')"
  echo "native dirs: ios=$( [ -d "$PROJ/ios" ] && echo yes || echo no) android=$( [ -d "$PROJ/android" ] && echo yes || echo no)"
  echo "ios bundle id: $(app_id ios)"; echo "android package: $(app_id android)"
  echo "xcode: $(xcodebuild -version 2>/dev/null | head -1 || echo missing)"
  echo "booted simulators:"; ios_booted | sed 's/^/  /'
  echo "android devices: $(adb_devices | tr '\n' ' ')"; echo "avds: $("$EMU" -list-avds 2>/dev/null | tr '\n' ' ')"
  cmd_metro status
  [ -z "$(metro_listeners)" ] && echo "  listeners on 8081-8099: none"
  echo "build lock: $(lock_holder || echo free)"
  local p; for p in ios android; do local c; c=$(ls -d "$CACHE/$p"-* 2>/dev/null | wc -l | tr -d ' '); echo "cached $p builds: $c"; done
  echo "free disk: $(free_gb) GB$( [ "$(free_gb)" -lt 15 ] && echo ' (LOW: build one platform at a time)')"
  echo "agent-device:"; agent_sessions | sed 's/^/  /'
}
cmd_cleanup() {
  cmd_metro stop; rm -f "$STATE/kv/active_platform"
  local app; app=$(sget ios_jslocation_app)
  if [ -n "$app" ] && [ -n "$(sget ios_udid)" ]; then
    xcrun simctl spawn "$(sget ios_udid)" defaults delete "$app" RCT_jsLocation >/dev/null 2>&1; rm -f "$STATE/kv/ios_jslocation_app"
    say "removed RCT_jsLocation for $app"
  fi
  if [ "${1:-}" = --shutdown ]; then
    [ -n "$(sget ios_udid)" ] && xcrun simctl shutdown "$(sget ios_udid)" 2>/dev/null && say "shut down simulator $(sget ios_udid)"
    alive "$(sget emulator_pid)" && { "$ADB" -s "$(sget android_serial)" emu kill >/dev/null 2>&1; say "stopped emulator"; }
    rm -f "$STATE/kv/ios_booted_by_rnqa" "$STATE/kv/emulator_pid"
  fi
  say "agent-device sessions still open (close each with the agent-device MCP 'close' tool):"
  agent_sessions | sed 's/^/  /'
}

usage() {
  cat <<EOF
rn-qa.sh <command>      (project: $PROJ)
  doctor                       detected config, devices, Metro ports 8081-8099, stale sessions, disk
  fingerprint ios|android      native fingerprint used as the build cache key
  build ios|android [--detach] build once per fingerprint (cached), serialized by a lock
  wait build|metro|app [ios|android] [--timeout S]   exit 0 done, 1 failed, 2 still running
  install ios|android          install cached build (boots a simulator/emulator if needed)
  metro start|stop|status [--port N] [--force]   one Metro per worktree, own port
  launch ios|android [--no-prewarm]
  status                       real state of build, artifacts, Metro, devices
  cleanup [--shutdown]         stop Metro, remove adb reverse, list agent-device sessions to close
  --no-skip (any command)      ignore "skip" in .claude/mobile-qa.json (same as RN_QA_NO_SKIP=1)
  --force-parallel (any command)  allow build/install/launch while the other platform is active (RN_QA_FORCE_PARALLEL=1)
Exit codes: 0 ok, 1 error, 2 still running (wait), 3 platform skipped by "skip" in mobile-qa.json,
  4 refused: the other platform is still active in this worktree (Metro+launch, rn-qa-booted device, or its build lock)
EOF
}

main() {
  local args=() a
  for a in "$@"; do case "$a" in --no-skip) NO_SKIP=1 ;; --force-parallel) FORCE_PARALLEL=1 ;; *) args+=("$a") ;; esac; done
  set -- ${args[@]+"${args[@]}"}
  local c=${1:-help}; [ $# -gt 0 ] && shift
  case "$c" in
    doctor) cmd_doctor ;;
    fingerprint) fingerprint "${1:-}" ;;
    build) cmd_build "$@" ;;
    wait) cmd_wait "$@" ;;
    install) cmd_install "${1:-}" ;;
    metro) cmd_metro "$@" ;;
    launch) cmd_launch "$@" ;;
    status) cmd_status ;;
    cleanup) cmd_cleanup "${1:-}" ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
  esac
}

# Log every command's output under the state dir (the build child logs to its own file).
if [ -z "${RN_QA_TEED:-}" ] && [ "${2:-}" != --_child ] && [ "${3:-}" != --_child ]; then
  RN_QA_TEED=1 "$BASH" "$SELF" "$@" 2>&1 | tee -a "$STATE/rn-qa.log"
  exit "${PIPESTATUS[0]}"
fi
main "$@"
