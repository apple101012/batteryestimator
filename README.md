# Battery Usage

A native macOS menu bar app that shows battery percentage, charging state, estimated time remaining or time to full, and the top active processes using CPU and memory.

This started as a SwiftBar plugin. The current release is a standalone Mac app, so users do not need SwiftBar.

## Install

Download the latest `BatteryUsage-1.0.1.pkg` from GitHub Releases, open it, and follow the installer.

The installer places `Battery Usage.app` in `/Applications`. Launch it once from Applications. From the menu bar dropdown, turn on **Open at Login** if you want it to start automatically.

## Features

- Native macOS menu bar app
- Battery percent and estimated time in the menu bar
- Charging, discharging, full, and source details
- Approximate top energy users based on CPU and memory
- Activity Monitor shortcut
- Optional Open at Login setting
- Legacy SwiftBar plugin kept in the repo for people who still want it

## Build Locally

```sh
scripts/package-release.sh
```

This creates:

- `build/Battery Usage.app`
- `dist/BatteryUsage-1.0.1.pkg`
- `dist/BatteryUsage-1.0.1.zip`

## Release

```sh
scripts/create-github-release.sh
```

Developer ID signing and notarization are not the same as GitHub ownership. GitHub identifies the source repo and release author. For the smoothest public macOS install experience, Apple requires a Developer ID certificate and notarization.
