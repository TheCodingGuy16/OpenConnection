# OpenConnection

**OpenConnection** is a free and open-source minimal browser launcher built on top of the Chromium engine. It provides a clean, text-based interface for launching Chromium in app mode — stripping away the browser chrome and opening any URL directly as a standalone window, perfect for kiosks, dashboards, or just a distraction-free browsing experience.

---

## Features

- Text-based GUI with arrow-key navigation and a clean rounded box UI
- Launches Chromium in app mode with a configurable URL and window size
- Live Chromium log streaming with session saving
- Session log viewer built into the interface
- Reset Data tool for clearing cache, history, and logs before redistribution
- Window auto-resizes dynamically based on the current page
- Consolas font set automatically for a clean look
- No installation required — just unzip and run

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or later (included with Windows)

---

## Installation

1. Download or clone this repository
```
   git clone https://github.com/TheCodingGuy16/OpenConnection.git
```

2. Double-click `openconnection.bat` to launch

> If Windows shows a security warning, right-click `oc_launcher.ps1` → Properties → check **Unblock** at the bottom, then try again.

---

## Configuration

On first launch, select **Configure and Launch** from the main menu. You can set:

- **URL** — the website to open in app mode
- **Width / Height** — the Chromium window dimensions

Settings are saved automatically to `config.ini`.

---

## Open Source

OpenConnection is released under the [MIT License](LICENSE). You are free to use, modify, and distribute it for any purpose. Contributions and pull requests are welcome.

Chromium is a separate open-source project maintained by Google and is bundled with this repository. It is licensed under the [BSD License](https://chromium.googlesource.com/chromium/src/+/main/LICENSE).
