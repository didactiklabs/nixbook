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

anya, a console-like machine, also auto-logs into SwayFX and starts **Steam Big Picture** with the session; hanamichi is an everyday desktop that just has Steam installed.

## Sunshine

`customNixOSModules.sunshine` runs the [Sunshine](https://github.com/LizardByte/Sunshine) game-streaming server (NVIDIA GameStream protocol) for **Moonlight** clients on any device:

- a user systemd service tied to the graphical session (restarts on crash);
- the binary wrapped with `cap_sys_admin` to capture display and audio without root;
- pair clients from the web UI at https://localhost:47990.

On anya it streams a **headless virtual display**, so the machine can be used remotely without a monitor attached. Moonlight Qt is installed on the laptops as the client.

## Wolf

`customNixOSModules.wolf` sets up [Wolf](https://games-on-whales.github.io/wolf/), a Moonlight-compatible streaming server that runs each session in its own container, with its firewall ports and the **wolf-den** web UI:

```nix
customNixOSModules.wolf = {
  enable = true;
  den.port = 8080;                    # wolf-den web UI (default)
  hostAppsStateFolder = "/etc/wolf";  # default
};
```

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
