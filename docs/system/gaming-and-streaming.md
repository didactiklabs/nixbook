# Gaming, streaming & sim racing

## Gaming

`customNixOSModules.gamingConfig` is a gaming setup inspired by Jovian-NixOS (SteamOS):

- **Steam** with Remote Play, **Proton GE** and **Proton CachyOS**, and extest (Steam Input on Wayland);
- **GameMode**;
- 32-bit graphics drivers;
- controller udev rules (uinput, Valve HID devices).

GPU tuning is selected with `gpu`:

| `gpu`      | Effect                                                                                              |
| ---------- | --------------------------------------------------------------------------------------------------- |
| `"amd"`    | AMD kernel parameters (TDR timeouts, TTM page pool, scheduler depth, IOMMU off), early `amdgpu` KMS |
| `"nvidia"` | No AMD tuning — configure the proprietary driver in the profile                                     |
| `"none"`   | Only the common stack                                                                               |

```nix
customNixOSModules.gamingConfig = {
  enable = true;
  gpu = "nvidia";
};
```

anya, a console-like machine, also auto-logs into SwayFX and starts **Steam Big Picture** with the session; hanamichi is an everyday desktop that just has Steam installed, and so is totoro, a laptop, with `gpu = "none"`: the `"amd"` tuning is for desktops (an 8 GB TTM page pool, IOMMU off). In Niri, games stay opaque and turn variable refresh rate on.

### Windows beside NixOS on anya

anya also has Windows, on the same EFI partition, and starts it by default: its firmware always starts the Linux boot menu, so `profiles/anya/dualboot.nix` makes Windows that menu's default. To get to NixOS, run `profiles/anya/linux.bat` from Windows (copy it there once): it restarts into NixOS for that one boot. From NixOS, a plain reboot goes back to Windows; `reboot-linux` restarts into NixOS again (use it from a remote session: Windows has neither ssh nor Sunshine). A Wake-on-LAN start lands in Windows.

## Sunshine

`customNixOSModules.sunshine` runs the [Sunshine](https://github.com/LizardByte/Sunshine) game-streaming server (NVIDIA GameStream protocol) for **Moonlight** clients on any device:

- a user systemd service tied to the graphical session (restarts on crash);
- the binary wrapped with `cap_sys_admin` to capture display and audio without root;
- announced on the network with Avahi (mDNS), so Moonlight finds the machine without typing its address;
- pair clients from the web UI at https://localhost:47990.

On anya it streams a **headless virtual display**, so the machine can be used remotely without a monitor attached: greetd starts SwayFX on wlroots' headless backend (`WLR_BACKENDS=headless,libinput`, still rendered on the GPU), whose virtual output `HEADLESS-1` rests at 2560×1440 at 60 Hz (`profiles/anya/khoa/swayConfig.nix`). The Desktop app (`profiles/anya/khoa/sunshine.nix`) switches it to each Moonlight client's own size and frame rate when a stream starts (`SUNSHINE_CLIENT_WIDTH`/`HEIGHT`/`FPS`) and back when it ends, so a 1080p laptop or a 120 Hz tablet gets native frames. A monitor plugged in stays dark. Sunshine starts after PipeWire's sound server, so a client reconnecting at boot has sound. Moonlight Qt is installed on the laptops as the client.

### Moonlight companion: Discord activity and game radio

Two things a streamed game can't do by itself, done by a pair of small services: `customNixOSModules.moonlightCompanion` on the machine running the games, `customHomeManagerModules.moonlightCompanion` on the one watching them.

```nix
# the game machine (anya)
customNixOSModules.moonlightCompanion = {
  enable = true;
  musicRadioDir = "/data/Steam/steamapps/common/Cyberpunk 2077/bin/x64/plugins/cyber_engine_tweaks/mods/MusicRadio/data";
};

# the watching machine (totoro)
customHomeManagerModules.moonlightCompanion = {
  enable = true; # Discord activity
  gameRadio = true; # Cyberpunk 2077's Music Radio station
};
```

**The link is Sunshine's own.** No ssh, no extra port, nothing to configure. Sunshine serves each app's cover picture to paired Moonlight clients; the game machine keeps a copy of the Desktop app's cover with a few text lines after the picture's end (it stays a valid picture), and the watching machine fetches it on Sunshine's port with Moonlight's own pairing, checking the host against the certificate kept when pairing. It only reads while Moonlight runs and a paired host is streaming. The link goes one way, from the game machine.

**Discord activity.** Discord only detects games running on its own computer. The game machine says which Steam game runs; the watching machine finds it in Discord's public list of known games (by Steam id, then by name) and announces it on Discord's local rich-presence socket, with the time the game started. In Vesktop the **Rich Presence (arRPC)** setting must be on. A game Steam doesn't run, or one Discord doesn't know, shows nothing.

**Game radio** (`gameRadio`, needs nixbook-shell). With the [Music Radio](https://www.nexusmods.com/cyberpunk2077/mods/38098) mod's in-game files installed in Cyberpunk 2077 (with RadioExt; without the mod's own companion program), its **Music (80.0)** station plays the [YouTube Music panel](/nixbook-shell/media#youtube-music-in-the-background): the music plays on the watching machine and gets the acoustics the game asks for (inside the car, beside it, tunnels, rain, clubs) as you move, mixed with the stream's sound. Picking the station resumes the music, leaving it pauses it, and the mod's next / previous / play-pause keys act on the panel's player. The game's now-playing card stays empty.

`journalctl --user -u moonlight-companion` on either machine says what it sees.

## Sim racing

`customNixOSModules.simracing` supports direct-drive wheelbases and peripherals from **Moza Racing** and **Fanatec**:

- udev rules for serial, HID (force feedback), USB and input access;
- **Foxblat** (Moza configuration tool, a Pit House alternative) and **Oversteer** (generic wheel manager: rotation, FFB gain, autocenter…);
- `evtest`, `fftest`, `jstest`;
- USB autosuspend disabled for the wheel hardware, `cdc_acm` for Moza serial.

Force feedback itself is handled natively by the kernel's PIDFF driver.

### Wheel presets (Home Manager)

| Module            | Hardware                   | What it deploys                                                                                                                                   |
| ----------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `foxblatConfig`   | Moza R9                    | FFB presets in `~/.config/foxblat/presets/` for Assetto Corsa Competizione, Assetto Corsa and Cyberpunk 2077 (wheel mod), pedal curves, autostart |
| `oversteerConfig` | Fanatec CSL DD / GT DD Pro | An ACC profile in `~/.config/oversteer/profiles/` (900°, autocenter off), applied at login                                                        |

::: info
Oversteer cannot set the Fanatec base tune (FFB strength, NDP/NFR/NIN/FEI): those live in the wheelbase firmware and are set on its OLED menu.
:::

Both require `customNixOSModules.simracing`.
