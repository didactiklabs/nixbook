# Hardware & power

## Laptops

`customNixOSModules.laptopProfile` — enable it on laptops:

- **lid switch**: suspend when closed, lock when on external power, ignore when docked;
- **power-profiles-daemon**: performance / balanced / power-saver profiles, switchable from the desktop shell;
- **power profile** (`laptopProfile.powerProfileOnBoot`, default `null`): the profile you choose (the bar's battery panel, the power button) is kept across reboots and deploys by power-profiles-daemon. Set it to `power-saver`, `balanced` or `performance` to start every boot from that one instead (one click left on _performance_ is hotter, louder, ~2–3× the power at light load);
- **CPU boost** (`laptopProfile.cpuBoost`, default `true`): `false` caps every core at its nominal frequency (on totoro 2.7 GHz instead of 4.77 GHz) — cooler, and more of the power budget for an integrated GPU in games, for slower single-thread work. Power profiles keep working: the cap is each core's `scaling_max_freq`, not the kernel's global boost switch, which makes power-profiles-daemon fail to change profile;
- **charge limit** (`laptopProfile.chargeLimit`, default `null`: none): the level (20–100 %) at which the battery stops charging, on laptops whose firmware has such a limit (`charge_control_end_threshold`). A battery kept at 100 % on the charger ages much faster than at 80 %. It is applied at boot and after each resume. `systemctl start battery-charge-limit@<percent>.service` (what [nixbook-shell's battery panel](/nixbook-shell/bar-and-panels#battery) does, no password for the person at the computer) sets another one and remembers it across reboots in `/var/lib/battery-charge-limit/limit`; delete that file to come back to the option's value; on ASUS laptops using nixos-hardware's battery module, its own `battery-charge-threshold` unit is turned off (it wrote 100 % at the same moment and could undo the limit at each boot or resume) and a `hardware.asus.battery.chargeUpto` other than 100 becomes the default when `chargeLimit` is `null`;
- **Wi-Fi power save** (`laptopProfile.wifiPowerSaveOnBattery`, default `true`): on battery the radio dozes between packets (less power), on the charger it stays awake (power save adds late wake-ups that made Moonlight streams stutter on totoro). Switched when the charger is plugged in or out and each time NetworkManager connects (it applies its own `wifi.powersave` at every connection); `false` leaves NetworkManager's setting alone;
- **thermald** thermal management (Intel CPUs only; it exits on AMD);
- **scx_lavd**, a sched_ext CPU scheduler built for interactivity and battery life (latency-critical tasks first, fewer cores awake);
- SATA link power management, deep sleep, and `powertop` for analysis.

Hardware quirks come from [nixos-hardware](https://github.com/NixOS/nixos-hardware), imported by each profile (e.g. `framework/13-inch/amd-ai-300-series`).

## Bluetooth audio auto-connect

`customNixOSModules.bluetoothAutoConnect` (on whenever Bluetooth is enabled) remembers the **last connected Bluetooth audio device** per user — a user service watches BlueZ for devices exposing an Audio Sink / Headset profile — and **reconnects it at login**, once PipeWire is up:

```nix
customNixOSModules.bluetoothAutoConnect = {
  attempts = 12; # default
  interval = 10; # seconds between attempts (default)
};
```

BlueZ is also told to retry after a lost link. The adapter must be powered at boot (`hardware.bluetooth.powerOnBoot`, set per profile).

## Printing and scanning

`customNixOSModules.printTools`:

- **CUPS** with driverless printing (IPP Everywhere), **ipp-usb** for USB printers/scanners;
- **Avahi** mDNS discovery of network printers;
- **SANE** with the airscan backend for network scanners, and **simple-scan**.

`cups-browsed` is deliberately disabled: its legacy auto-created queues silently drop jobs, and modern CUPS discovers printers natively. Add discovered printers from the CUPS web interface (http://localhost:631).

## Virtual machines

`customNixOSModules.vmSupport` adds the VirtIO drivers (`virtio_pci`, `virtio_blk`, `virtio_scsi`, `virtio_net`) to the initrd so the system boots under QEMU/KVM — useful with `test-iso` or VM images. Not needed on bare metal.

## Controllers and input devices

- **DualShock 4**: `ds4drv` user service (HID-raw + xpad emulation), from the `tools` module.
- Game-device udev rules and unprivileged uinput access.
- Steam controllers and Valve HID devices with the [gaming module](./gaming-and-streaming#gaming).
- Sim-racing wheelbases and pedals with the [sim racing module](./gaming-and-streaming#sim-racing).

## Displays

- Per-user monitor layout in the compositor configuration (Niri `outputs`, Sway `output`).
- `wdisplays` for arranging monitors graphically (with `desktopApps`).
- Night light: `wlsunset`, driven by nixbook-shell's night-light toggle.
- On NVIDIA, the Niri module installs the driver application profile that keeps Niri's VRAM usage from growing.
