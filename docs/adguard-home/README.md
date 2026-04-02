# AdGuard Home

Serveur DNS local avec blocage de publicités, déployé sur le cluster k3s via ArgoCD.

## Rôle

AdGuard Home fournit la résolution DNS pour le réseau local. Il redirige les domaines `*.home` vers Traefik (`192.168.1.151`) et utilise Quad9 + Cloudflare DoH comme upstream DNS.

## Configuration

| Paramètre | Valeur |
|---|---|
| Chart | `gabe565/adguard-home` v0.3.25 |
| Namespace | `networking` |
| Sync wave | 5 (déployé en dernier) |
| IP DNS (LoadBalancer) | `192.168.1.152` (TCP + UDP port 53) |
| Interface web | `http://adguard.home` (port 3000 via Ingress) |
| Node | `k3s-worker-01` (hostNetwork + nodeSelector) |
| Timezone | `Europe/Paris` |

## DNS Rewrites

Les domaines locaux sont redirigés vers l'IP Traefik :

| Domaine | Cible |
|---|---|
| `adguard.home` | `192.168.1.151` |
| `homepage.home` | `192.168.1.151` |
| `valhafin.home` | `192.168.1.151` |
| `grafana.home` | `192.168.1.151` |

## Upstream DNS

- `https://dns10.quad9.net/dns-query` (DNS-over-HTTPS)
- `https://dns.cloudflare.com/dns-query` (DNS-over-HTTPS)

## Stockage

- Config : 1 Gi (local-path)
- Data : 5 Gi (local-path)

## Particularités

- `hostNetwork: true` — le pod utilise le réseau de l'hôte directement (nécessaire pour le DNS)
- `dnsPolicy: ClusterFirstWithHostNet` — résolution DNS interne au cluster préservée malgré hostNetwork
- Le service DNS est exposé via MetalLB LoadBalancer sur une IP dédiée (`192.168.1.152`), séparée de Traefik
- `ServerSideApply=true` activé dans les syncOptions

## Fichiers

- Manifest ArgoCD : [`argocd-apps/adguard-home-app.yml`](../argocd-apps/adguard-home-app.yml)
- Pas de chart local — configuration inline dans le manifest ArgoCD
