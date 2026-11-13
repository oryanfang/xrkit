# xrkit

**An all‑in‑one tweak for jailbroken iOS 17** · [简体中文](README.zh-CN.md)

Home Screen, Lock Screen, Control Center and the App Switcher, each change behind its own switch. xrkit puts the small system tweaks you'd otherwise need several packages for into one settings page, and ships its own Control Center module loader with 15 modules. Written from scratch.

<p align="center">
  <img src="docs/screenshots/settings.png" width="30%" alt="Settings › xrkit">
  <img src="docs/screenshots/control-center.png" width="30%" alt="Control Center settings with xrkit's modules">
  <img src="docs/screenshots/homescreen.png" width="30%" alt="Home Screen settings">
</p>

Objective‑C / Logos, built with Theos, for **roothide** jailbreaks. Made for iOS 17 and **only tested on iOS 17.3.1**; some features may not work on other versions. The settings UI is in English and Chinese: it follows the system language, or pick one under About › Language.

## Features

**Home Screen**
- Hide: the home bar, the Today view, the App Library, page dots, the Search button, icon labels, notification badges.
- Folders: hide the background; show the folder as its first app's icon (the folder's badge still shows).
- Dock: hide it, background style (system / clear / dark / light), icon count (3–6; icons shrink to fit 6).
- Icons: badges take the app's main color, download percentage on installing apps, fade icons out when idle.
- Screenshots: skip the thumbnail in the corner and save straight to Photos.

**Lock Screen**
- Hide the flashlight / camera buttons, "Swipe up to open" and the Control Center hint in the top‑right corner.
- Disable swiping left for the camera and pulling down for Search.
- Go straight to the Home Screen after Face ID (optionally stay on the Lock Screen when there are notifications).
- Battery percentage while charging; the Now Playing card can collapse when paused or stay hidden.

**Control Center**
- Background and module transparency, module corner radius, hide the status bar.
- Percentages on the brightness and volume sliders.
- Module loader (a CCSupport replacement): loads third‑party modules, and the built‑in fixed modules can be moved and removed.
- Built‑in modules: respring, lock, screenshot, auto‑brightness, clear apps, xrkit settings, VPN (long‑press to switch), dark mode, Night Shift, True Tone, keep awake, personal hotspot, location, live network speed, battery info.

**App Switcher**
- Layout: system (stack) / grid / iPad.
- Hide card titles and icons, long‑press to lock an app (locked apps can't be swiped away), pull down on any card to clear all.
- Card size, corner radius, spacing and vertical position.

**Beta**
- Mac‑style Dock: dots under running apps, and recent apps to the right of a divider.

**About page**
- Language (System / 中文 / English), check GitHub for a new version, report an issue, copy debug info (versions, device model and changed settings; not which apps you locked), reset all settings.

Settings live in Settings › xrkit. Some options need a respring; the settings page marks them.

## Install

Add the source `https://oryanfang.github.io/repo/` in Sileo or Zebra and install **xrkit**. Or download the `.deb` from [Releases](https://github.com/oryanfang/xrkit/releases).

roothide only (package architecture `iphoneos-arm64e`). For rootless / rootful you need to change the packaging yourself, see [BUILDING.md](BUILDING.md).

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE): free for personal study, research and other noncommercial use; commercial use is not allowed.
