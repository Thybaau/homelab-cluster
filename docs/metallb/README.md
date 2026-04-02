# MetalLB

Load balancer bare-metal en mode L2 pour le cluster k3s. Attribue des IPs externes aux services de type `LoadBalancer`.

## Rôle

MetalLB permet d'utiliser des services Kubernetes de type `LoadBalancer` dans un environnement bare-metal (sans cloud provider). Il annonce les IPs via ARP (mode L2) sur le réseau local.

## Configuration

| Paramètre | Valeur |
|---|---|
| Chart | `metallb/metallb` v0.14.9 (officiel) + config locale |
| Namespace | `metallb-system` |
| Sync wave | 0 (déployé en premier) |
| Pool IP | `192.168.1.151 - 192.168.1.170` |
| Mode | L2 (Layer 2 / ARP) |

## Architecture

L'application ArgoCD utilise deux sources :
1. Le chart officiel MetalLB (installation du controller + speakers)
2. Le chart local `helm/metallb/` (configuration de l'IP pool et L2 advertisement)

## Ressources déployées par le chart local

- `IPAddressPool` — définit la plage d'IPs disponibles (`192.168.1.151-170`)
- `L2Advertisement` — active l'annonce ARP pour cette pool

## IPs attribuées

| IP | Service |
|---|---|
| `192.168.1.151` | Traefik (Ingress Controller) |
| `192.168.1.152` | AdGuard Home (DNS) |

## Fichiers

- Manifest ArgoCD : [`argocd-apps/metallb-app.yml`](../argocd-apps/metallb-app.yml)
- Chart Helm local : [`helm/metallb/`](../helm/metallb/)
  - `templates/ip-address-pool.yaml` — Définition de la pool IP
  - `templates/l2-advertisement.yaml` — Configuration L2
