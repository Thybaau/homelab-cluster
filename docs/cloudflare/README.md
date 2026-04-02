# Cloudflare Tunnel

Tunnel Cloudflare pour exposer les services du cluster sur Internet via les domaines `*.caremelle.org`, sans ouvrir de ports sur le routeur.

## Rôle

Cloudflared établit un tunnel sortant vers le réseau Cloudflare. Les requêtes entrantes sur les domaines publics sont routées à travers ce tunnel vers les services internes du cluster.

## Configuration

| Paramètre | Valeur |
|---|---|
| Chart | Local (`helm/cloudflare/`) |
| Namespace | `networking` |
| Sync wave | 3 |
| Image | `cloudflare/cloudflared:latest` |
| Réplicas | 1 |

## Ressources

| | Request | Limit |
|---|---|---|
| CPU | 50m | 200m |
| Mémoire | 64Mi | 128Mi |

## Secrets

Le token du tunnel est stocké dans un SealedSecret (`TUNNEL_TOKEN`) défini dans `helm/cloudflare/values.yaml`. Ce token est généré depuis le dashboard Cloudflare Zero Trust.

## Fichiers

- Manifest ArgoCD : [`argocd-apps/cloudflare-app.yml`](../argocd-apps/cloudflare-app.yml)
- Chart Helm : [`helm/cloudflare/`](../helm/cloudflare/)
  - `templates/deployment.yaml` — Deployment cloudflared
  - `templates/sealedsecret.yaml` — SealedSecret du token tunnel
