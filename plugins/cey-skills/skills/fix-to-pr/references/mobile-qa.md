# Native mobile QA (iOS simulator / Android emulator)

Procedure for the QA driver on a React Native app (Expo CNG, Expo with committed `ios/`/`android/`, or bare RN). All setup goes through one script, so every step is non-interactive, has a timeout, and leaves state the lead can read. The lead pastes the script's absolute path into your brief. Run it from the app's root (the worktree):

```sh
RNQA=/absolute/path/from/the/brief/scripts/rn-qa.sh   # fallback only: ${CLAUDE_PLUGIN_ROOT:-}/skills/fix-to-pr/scripts/rn-qa.sh
bash "$RNQA" help
```

Builds are cached by native fingerprint and shared across worktrees, so a JS-only fix reuses the last build and skips the 6–18 minute native build. Each worktree gets its own Metro on its own port, so parallel sessions never share or kill each other's bundler.

## Steps

1. **Load tools first.** Load deferred tools with ToolSearch before calling them (`select:mcp__agent-device__open,mcp__agent-device__press,...`). A tool whose schema isn't loaded fails, and a failed wait/notify call means nothing will wake you.
2. **Doctor.** `bash "$RNQA" doctor`. It shows project type, bundle id/package, booted devices, the Metros on ports 8081–8099 and their worktrees, open agent-device sessions, and free disk. A fresh worktree has no `node_modules`: run the repo's install (`npm ci`, or the lockfile's tool) before anything else. It takes about 1–3 minutes and every later step needs it.
3. **Platforms: iOS by default, one at a time.**
   - **Default is the iOS simulator only.** Run Android only when the brief says the user opted in (then after iOS), or instead of iOS when the brief says the bug is Android-only. Report a platform that wasn't picked as `SKIPPED (not selected)`.
   - **Repo skip wins.** Platforms listed in `skip` (doctor prints `skip: <platform> (<reason>)`) are not driven even if picked: report every item on them as `SKIPPED (<reason>)`, never as pass. `build`/`install`/`launch` on a skipped platform print `SKIPPED: ...` and exit 3. Pass `--no-skip` (or `RN_QA_NO_SKIP=1`) only when the brief explicitly asks you to verify that platform.
   - **Never two platforms at once** (it lags the machine; parallel builds have filled the disk and wedged adb). Start the second platform only after the first is fully done: all its items finished, its agent-device session closed, `bash "$RNQA" cleanup` run, and, if rn-qa or you booted that simulator/emulator, `cleanup --shutdown`. The script enforces this: `build`/`install`/`launch` of one platform exit 4 while this worktree still has the other platform launched with Metro up, a simulator/emulator rn-qa booted for it still running, or a build of it holds the lock. Don't pass `--force-parallel` unless the brief says so.
4. **Build.** `bash "$RNQA" build ios --detach`, then `bash "$RNQA" wait build` in the foreground. Each call blocks for at most 100 s, which fits the Bash tool's default 120 s timeout. Exit 0 means done (or a cache hit), 1 means failed (it prints the last 40 log lines), and 2 means it is still running. Exit 2 is normal: call `wait build` again. To block longer, pass `--timeout 540`, but only with the Bash tool's `timeout: 600000`. Never idle while waiting for a notification. Never write `sleep`/`grep` poll loops, and don't use Monitor unless you loaded its schema. The `osascript ... "Simulator"` error at the end of `expo run:ios` is not fatal: the script checks for the `.app`.
5. **Install, Metro, launch.**
   ```sh
   bash "$RNQA" install ios        # boots a simulator/emulator if none is booted
   bash "$RNQA" metro start        # this worktree's Metro: 8081 if free, else the first free port 8082-8099
   bash "$RNQA" launch ios         # points the app at that port, pre-warms the bundle, launches, waits up to 90 s for "JS bundle served"
   ```
   - **Bash timeout.** `install` can boot a device and `launch` can pre-warm a cold bundle, so give these calls the Bash tool's `timeout: 600000`.
   - **Port wiring.** Android: `adb reverse tcp:8081 tcp:<port>`, since the app always asks for 8081 on the device. iOS: the `RCT_jsLocation` user default and launch argument (`localhost:<port>`), which `RCTBundleURLProvider` reads.
   - **One emulator, one reverse.** Two worktrees can't share one Android emulator at the same time, because the last `launch` wins the reverse. Use a second emulator, or take turns.
   - **Choosing a port.** `--port N` or `RN_QA_PORT` picks a port yourself.
   - **Never kill another session's Metro.** `metro stop --force [--port N]` kills a Metro from another worktree. Use it only when `doctor` shows that worktree has no running rn-qa build and no agent-device session.
   - **No "JS bundle served" line.** `launch` warns instead. Take a snapshot before driving: the app may still show "Bundling…".
   - **After a code change.** Metro runs with `CI=1`, so it doesn't watch files. Run `metro stop`, `metro start`, then `launch` again.
6. **Drive with agent-device.** Call `open` once per platform, drive with `press`/`fill`/`scroll` (`settle: true`), and verify with `wait`/`is`/`get` plus screenshots. Call `close` at the end. Don't call agent-device while a native build is running: its runner xcodebuild then times out after 91–151 s per call. On `DEVICE_IN_USE`, close the stale session named in the error (doctor lists them) instead of creating new simulators. On Android, if the snapshot shows another app (Play Store, Gmail), run `launch android` again.
7. **Time budget.** QA setup (build + install + launch) gets 25 minutes, and the whole QA run gets 45. Over budget, stop and report BLOCKED with the output of `bash "$RNQA" status` and the last log lines.
8. **Cleanup, always**, pass or fail: `bash "$RNQA" cleanup` (stops this worktree's Metro and removes its adb reverse and `RCT_jsLocation`), then `close` every agent-device session it lists that you opened. Add `--shutdown` only if you booted the device yourself.
9. **Never** `rm -rf ios android` (that throws away the prebuild and pods for the next run), never run `eas build` locally, and never delete the rn-qa cache.

Report per item and per platform: pass/fail, screenshot path, device log errors. Include the fingerprint and whether the build was a cache hit.

## Repo overrides: `.claude/mobile-qa.json`

Optional. Every field is optional, and the script falls back to `expo config`, then to the native project files.

```json
{
  "platforms": ["ios", "android"],
  "ios": { "bundleId": "com.example.app", "scheme": "Example", "device": "iPhone 17" },
  "android": { "package": "com.example.app", "avd": "Medium_Phone_API_36.0" },
  "env": { "EXPO_PUBLIC_API_URL": "https://dev-api.example.com" },
  "skip": { "android": "why this platform is parked; remove once fixed" },
  "login": "path to a doc, or text describing the test-login technique",
  "notes": "anything else the QA driver must know"
}
```

- `platforms`: the platforms this app ships on. Skip the others. This does not opt in to Android QA: the default is still iOS only.
- `env`: exported for every command (build, fingerprint, Metro). Use it to point the bundle at a dev API instead of prod. `APP_VARIANT`-style variables change the bundle id and the fingerprint.
- `skip`: platforms to leave out of QA for now, each with a non-empty reason (any platform key). It wins over the user's QA platform choice. The script refuses to build, install or launch them (exit 3) unless given `--no-skip` / `RN_QA_NO_SKIP=1`. Items on a skipped platform are reported as `SKIPPED (<reason>)`.
- `login`, `notes`: read them before driving the app.

State and logs live in `${RN_QA_HOME:-~/.cache/rn-qa}/<project>/<worktree>/`, and builds in `.../<project>/cache/` (3 per platform are kept).
