# Homepage

Dashboard homelab basé sur [homepage.dev](https://gethomepage.dev), affichant les services, widgets de monitoring et liens rapides.

## Rôle

Homepage fournit une page d'accueil centralisée pour le homelab avec des widgets interactifs (Proxmox, ArgoCD, Grafana, AdGuard, Tailscale) et des liens vers tous les services.

## Configuration

| Paramètre | Valeur |
|---|---|
| Chart | Local (`helm/homepage/`) |
| Namespace | `homepage` |
| Sync wave | 1 |
| Image | `ghcr.io/gethomepage/homepage:latest` |
| Accès | `http://homepage.home` / `http://homepage.caremelle.org` |

## Ressources

| | Request | Limit |
|---|---|---|
| CPU | 100m | 500m |
| Mémoire | 128Mi | 512Mi |

## Widgets configurés

| Widget | Source | Credentials |
|---|---|---|
| Proxmox | `https://192.168.1.200:8006` | SealedSecret `homepage-proxmox` |
| ArgoCD | `http://192.168.1.102:30080` | SealedSecret `homepage-argocd` |
| Grafana | Service interne cluster | Variable `HOMEPAGE_VAR_GRAFANA_PASSWORD` |
| AdGuard Home | Service interne cluster | — |
| Tailscale | API Tailscale | Variable `HOMEPAGE_VAR_TAILSCALE_KEY` |

## Services affichés

- **Applications** : Valhafin
- **Monitoring** : Grafana
- **Network** : AdGuard Home, Tailscale (3 devices)

## Interface

- Thème : dark
- Couleur : slate
- Header : boxed
- Titre : "Homelab Dashboard"

## Guides détaillés

- [Guide de déploiement](deployment-guide.md)
- [Guide de configuration](configuration-guide.md)
- [Guide de maintenance](maintenance-guide.md)

## Fichiers

- Manifest ArgoCD : [`argocd-apps/homepage-app.yml`](../argocd-apps/homepage-app.yml)
- Chart Helm : [`helm/homepage/`](../helm/homepage/)
