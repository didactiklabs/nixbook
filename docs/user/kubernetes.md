# Kubernetes

## Toolchain

`customHomeManagerModules.kubeTools` installs a complete Kubernetes toolbox:

| Category           | Tools                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| Core               | kubectl (`k`), Helm, kustomize, kubelogin (OIDC), kubeswitch                                                             |
| Dashboards & TUIs  | [k9s](#k9s), [sofka](/packages/#sofka) (`ki`), [crd-wizard](/packages/#crd-wizard), [kl](/packages/#kl) (multi-pod logs) |
| Inspection         | kubectl-neat, kubectl-view-secret, kubectl-explore, skopeo, dive, netfetch                                               |
| GitOps & platforms | Flux CLI, [kratix-cli](/packages/#kratix-cli), virtctl (KubeVirt), paralus-cli                                           |
| Development        | kubebuilder, kind                                                                                                        |
| Storage            | [pvmigrate](/packages/#pvmigrate)                                                                                        |
| Custom             | [songbird](/packages/#songbird)                                                                                          |

Shell aliases: `k` → kubectl, `ki` → sofka; Zsh completions for kubectl and songbird. The [Starship prompt](./shell#starship-prompt) shows the current context.

## Kubeconfigs

`customHomeManagerModules.kubeConfig.<org>.enable` deploys an organisation's **OIDC kubeconfigs** into `~/.kube/configs/<org>/`, where kubeswitch finds them:

| Option         | Kubeconfigs                                          |
| -------------- | ---------------------------------------------------- |
| `didactiklabs` | `oidc@didactiklabs.kubeconfig`                       |
| `bealv`        | `oidc@bealv.kubeconfig`, `oidc@bealvprod.kubeconfig` |
| `rpcu`         | `oidc@mgmt.kubeconfig` (Zitadel)                     |
| `logicmg`      | `oidc@logicmg.kubeconfig`                            |

No credentials are stored: you authenticate through your browser with kubelogin when a context is first used.

## kubeswitch

`customHomeManagerModules.kubeswitchConfig` configures [kubeswitch](https://github.com/danielfoehrKn/kubeswitch) as **`kswitch`** (alias `ks`): a fuzzy picker over every context in every kubeconfig under `~/.kube/configs/`, with per-shell isolation instead of juggling `KUBECONFIG`.

```bash
ks                 # pick a context
ks configs/admin@prod
```

[AI workspaces](./ai-workspaces) can import selected kubeswitch contexts through the `infra/kubeswitch` ocm module.

## k9s

`k9sConfig` (part of `kubeTools`) ships the k9s configuration and plugins — including **Shift+E** to open the CRD visualiser ([crd-wizard](/packages/#crd-wizard)) on a resource.
