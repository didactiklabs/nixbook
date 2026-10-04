# The fleet

Nixbook manages five machines. Each is a node in `hive.nix` and a directory in `profiles/`; the profile is chosen automatically from the hostname.

| Machine                           | Role                               | User          | Compositor | Desktop shell                             |
| --------------------------------- | ---------------------------------- | ------------- | ---------- | ----------------------------------------- |
| [totoro](./profiles#totoro)       | Main development laptop            | khoa          | Niri       | nixbook-shell                             |
| [tanjiro](./profiles#tanjiro)     | Development laptop (Framework 13)  | khoa          | Niri       | nixbook-shell                             |
| [nishinoya](./profiles#nishinoya) | Development laptop                 | aamoyel       | Niri       | DankMaterialShell                         |
| [hanamichi](./profiles#hanamichi) | Everyday & gaming desktop (NVIDIA) | chocomooncake | Niri       | nixbook-shell                             |
| [anya](./profiles#anya)           | Gaming & streaming desktop (AMD)   | khoa          | SwayFX     | Steam Big Picture (nixbook-shell enabled) |

## Feature matrix

Which optional features each machine switches on:

| Feature                                                                 | totoro | tanjiro | nishinoya | hanamichi  |    anya    |
| ----------------------------------------------------------------------- | :----: | :-----: | :-------: | :--------: | :--------: |
| [Laptop power profile](/system/hardware#laptops)                        |   ✓    |    ✓    |     ✓     |            |            |
| [Secure Boot](/installation/secure-boot)                                |   ✓    |    ✓    |           |            |            |
| [greetd login](/desktop/login)                                          |   ✓    |    ✓    |     ✓     |     ✓      | auto-login |
| [Firewall](/system/security#firewall)                                   |        |    ✓    |           |            |            |
| [Tailscale / NetBird](/system/networking)                               |   ✓    |    ✓    |     ✓     |     ✓      |            |
| [Gaming (Steam, Proton, GameMode)](/system/gaming-and-streaming#gaming) |        |         |           | ✓ (NVIDIA) |  ✓ (AMD)   |
| [Sim racing](/system/gaming-and-streaming#sim-racing)                   |        |         |           |     ✓      |     ✓      |
| [Sunshine streaming](/system/gaming-and-streaming#sunshine)             |        |         |           |            |     ✓      |
| [Printing & scanning](/system/hardware#printing-and-scanning)           |        |         |           |     ✓      |            |
| [Vietnamese input (Lotus)](/system/input-methods)                       |   ✓    |    ✓    |           |     ✓      |            |
| [Kubernetes tools](/user/kubernetes)                                    |   ✓    |    ✓    |     ✓     |            |            |
| [Dev tools & AI workspaces](/user/development)                          |   ✓    |    ✓    |     ✓     |            |            |

See [Machine profiles](./profiles) for the details, and [Adding a machine](./adding-a-machine) to add your own.
