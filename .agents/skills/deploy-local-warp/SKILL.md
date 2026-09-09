---
name: deploy-local-warp
description: Build a local Warp app bundle from source and install it to /Applications on macOS, replacing the current daily driver. Use this whenever the user wants to install their local Warp build, update the app on their Mac, deploy the latest source to /Applications, replace the old Warp with the dev build, or bundle and ship a local binary to the system Applications folder. Also use when the user says "redeploy," "deploy again," or wants to push a fresh build after code changes.
---

# deploy-local-warp

Build the Warp macOS app from the local checkout and install it to `/Applications`.

## Overview

This skill handles the complete end-to-end flow of turning a local `warp-oss` (or `warp`) checkout into a runnable `.app` bundle on macOS and replacing whatever version is currently in `/Applications`. It is designed for developers who use a stable/daily Warp binary but also iterate on the open-source codebase and want to quickly test their own build as their primary terminal.

## Steps

### 1. Build the binary and bundle

Change into the `app/` crate and run `cargo bundle`. Use `TERM=xterm NO_COLOR=1` as environment overrides because `cargo-bundle`'s terminal color detection can panic with `ColorOutOfRange` on some macOS terminal setups.

```bash
cd app
TERM=xterm NO_COLOR=1 cargo bundle --bin warp-oss --features gui
```

For a **release** build:

```bash
cd app
TERM=xterm NO_COLOR=1 cargo bundle --bin warp-oss --features gui --release
```

Wait for this to finish. It produces a `.app` bundle under `target/debug/bundle/osx/WarpOss.app` (or `target/release/bundle/osx/WarpOss.app`).

### 2. Run macOS post-bundle preparation

The bare `.app` produced by `cargo bundle` is not quite ready. Run the project's own scripts to update the plist, copy bundled resources, compile the app icon, and re-codesign.

Chain these in a single shell command so that any failure aborts the sequence:

```bash
cd <repo-root>
WARP_APP_PATH="target/debug/bundle/osx/WarpOss.app"
WARP_CHANNEL="oss"
WARP_BIN_NAME="warp-oss"

# Add framework rpath (needed for Sentry and other frameworks)
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$WARP_APP_PATH/Contents/MacOS/$WARP_BIN_NAME" 2>/dev/null || true

# Update Info.plist with URL schemes, permissions, etc.
WARP_SCHEME_NAME="warposs" WARP_PLIST_PATH="$WARP_APP_PATH/Contents/Info.plist" \
  ./script/update_plist

# Copy bundled resources (skills, icons, bootstraps)
SKIP_SETTINGS_SCHEMA=1 NO_LICENSES=1 \
  ./script/prepare_bundled_resources \
  "$WARP_APP_PATH/Contents/Resources" "$WARP_CHANNEL"

# Compile adaptive icon (safe to skip if icon bundle missing)
./script/compile_icon "$WARP_CHANNEL" "$WARP_APP_PATH" || true

# Re-codesign with the local Apple Development cert
SIGNING_CERT="$(security find-identity -p codesigning -v | grep "Apple Development" | awk '{print $2}' | head -1)"
codesign --force --deep --options runtime \
  --sign "${SIGNING_CERT:--}" "$WARP_APP_PATH" \
  --entitlements script/Debug-Entitlements.plist
```

For a **local/internal** build, change the variables:

- `WARP_APP_PATH="target/debug/bundle/osx/WarpLocal.app"`
- `WARP_BIN_NAME="warp"`
- `WARP_CHANNEL="local"`
- `WARP_SCHEME_NAME="warplocal"`

### 3. Install into /Applications

Back up the existing app first, then replace it with the freshly built bundle:

```bash
# Optional: back up old version
mv /Applications/WarpOss.app /Applications/WarpOss.app.backup

# Install the new build
cp -R "$WARP_APP_PATH" /Applications/
```

### 4. Verify

Confirm the new binary is in place and has a recent timestamp:

```bash
ls -la /Applications/WarpOss.app/Contents/MacOS/warp-oss
```

## Common issues

### cargo-bundle panics with `ColorOutOfRange`

If you see:

```
thread 'main' panicked at src/main.rs:164:37:
called `Result::unwrap()` on an `Err` value: Error(Term(ColorOutOfRange), ...)
```

Run the bundle step with `TERM=xterm NO_COLOR=1` as shown above. This disables the ANSI-color auto-detection that triggers the bug.

### Missing "Apple Development" cert

If `security find-identity` returns nothing, `codesign` will fall back to ad-hoc signing (`--sign -`). That is fine for local-only use, but you may see a Gatekeeper warning on first launch. Go to **System Settings > Privacy & Security** and click **Open Anyway**.

### App still looks like the old version after reinstall

Check the timestamps of the bare binary, the bundle binary, and the installed binary:

```bash
ls -la target/debug/warp-oss
ls -la target/debug/bundle/osx/WarpOss.app/Contents/MacOS/warp-oss
ls -la /Applications/WarpOss.app/Contents/MacOS/warp-oss
```

If the bundle timestamp is older than the bare binary, the bundle was created before the latest compilation. Re-run `cargo bundle` to refresh it, then repeat the post-bundle prep and copy steps.

## Restoring the old version

If the new build is broken, restore the backup:

```bash
rm -rf /Applications/WarpOss.app
mv /Applications/WarpOss.app.backup /Applications/WarpOss.app
```
