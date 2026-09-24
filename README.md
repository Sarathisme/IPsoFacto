# IPso Facto

A tiny macOS menu bar utility that shows your Mac's current LAN IP address,
right where you'd look for it — no more opening System Settings just to read
off a `192.168.x.x`.

<img src="Resources/AppIcon-1024.png" width="160" alt="IPso Facto app icon: a magnifying glass inspecting a Wi-Fi signal">

[![Download IPso Facto](https://img.shields.io/badge/Download-IPso%20Facto-F36F56?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Sarathisme/IPsoFacto/releases/latest/download/IPsoFacto.zip)

Every push to `main` is built and signed automatically — the button above
always points at the latest build. It's ad-hoc signed, not notarized, so
the first time you open it macOS will warn that it's from an unidentified
developer: right-click (or Control-click) the app in Finder and choose
**Open**, then confirm, to get past that one-time prompt.

## What it does

- Shows the active network interface's address as plain text in the menu
  bar (e.g. `192.168.1.4`), not just an icon — switch between **IPv4** and
  **IPv6** from the dropdown, and it remembers your choice.
- Updates live — on network changes, DHCP lease renewals, VPN connect, and
  wake from sleep — usually within a couple of seconds.
- Skips loopback, VPN/tunnel interfaces, and other virtual adapters so you
  always see your real LAN address, even with a VPN active.
- Click the menu bar item for a small dropdown: interface name, an **IPv4
  / IPv6** toggle, a **QR code** of the current address for scanning with
  your phone, **Copy IP Address**, a **Launch at Login** toggle, About,
  and Quit.
- Runs as a true background utility: no Dock icon, no Cmd-Tab entry.
- Launches at login via `SMAppService` (macOS's modern login-item API).

## Requirements

- macOS 13 or later.
- To build: Swift 6.1+ toolchain. Xcode is *not* required — this project
  builds and packages entirely from the Command Line Tools.

## Building and installing

```sh
git clone <this-repo-url>
cd IPsoFacto

# Build + assemble a signed .app and install it to /Applications
Scripts/build-app.sh

open /Applications/IPsoFacto.app
```

`Scripts/build-app.sh` builds a release binary, assembles a real `.app`
bundle around it (with `Info.plist`, `LSUIElement=true` to hide the Dock
icon, and the app icon), ad-hoc signs it, and installs it to
`/Applications` — `SMAppService` login-item registration needs a stable,
standard install location to work correctly.

## Running tests

```sh
Scripts/run-tests.sh
```

This wraps `swift test` with the flags needed to find `Testing.framework`
on a Command-Line-Tools-only machine (no Xcode installed). The test suite
covers `AddressResolver`, the pure function that picks which address to
display — interface priority, VPN/tunnel exclusion, link-local handling,
and multi-address interfaces — with no live network required.

## Project layout

```
Sources/IPsoFactoCore/   Pure, unit-tested address-selection logic
Sources/IPsoFacto/       App shell: status item, menu, network monitor,
                          login-item integration
Tests/IPsoFactoCoreTests/ Unit tests for IPsoFactoCore
Resources/                Info.plist and app icon (source + built .icns)
Scripts/                  Build, test, and icon-generation helpers
```

## Name

A pun on *ipso facto* ("by the very fact itself") — the app tells you your
IP, by the fact of just being open. The icon plays the same joke: a
magnifying glass catching a Wi-Fi signal in the act.
