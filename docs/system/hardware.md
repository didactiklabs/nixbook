# Hardware & power

## Laptops

`customNixOSModules.laptopProfile` — enable it on laptops:

- **lid switch**: suspend when closed, lock when on external power, ignore when docked;
- **power-profiles-daemon**: performance / balanced / power-saver profiles, switchable from the desktop shell;
- **thermald** thermal management;
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
