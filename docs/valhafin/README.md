# Valhafin

Application de gestion de portefeuille financier déployée sur le cluster k3s. Backend Go, frontend React, base de données PostgreSQL.

## Rôle

Valhafin connecte des comptes d'investissement (Trade Republic, Binance, Bourse Direct), synchronise automatiquement les transactions, et visualise la performance du portefeuille.

## Configuration

| Paramètre | Valeur |
|---|---|
| Chart | Local (`helm/valhafin/`) |
| Namespace | `valhafin` |
| Sync wave | 1 |
| Accès | `http://valhafin.home` |

## Composants déployés

### Backend (Go)

| Paramètre | Valeur |
|---|---|
| Image | `ghcr.io/thybaau/valhafin/backend:1.0.6` |
| Port | 8080 |
| Health check | `GET /health` |
| CPU | 100m request / 500m limit |
| Mémoire | 128Mi request / 512Mi limit |

### Frontend (React)

| Paramètre | Valeur |
|---|---|
| Image | `ghcr.io/thybaau/valhafin/frontend:1.0.6` |
| Port | 80 |
| Health check | `GET /health` |
| CPU | 50m request / 200m limit |
| Mémoire | 64Mi request / 256Mi limit |

### Base de données (PostgreSQL)

| Paramètre | Valeur |
|---|---|
| Image | `postgres:15-alpine` |
| Port | 5432 |
| Stockage | 10 Gi (PVC) |
| Node | `k3s-worker-01` (nodeSelector pour local-path) |
| CPU | 250m request / 1000m limit |
| Mémoire | 256Mi request / 1Gi limit |

## Ingress

Traefik route les requêtes selon le path :

| Path | Service |
|---|---|
| `/api/*` | Backend (port 8080) |
| `/*` | Frontend (port 80) |

## Secrets

Deux SealedSecrets sont déployés (sync-wave `-1`, avant les pods) :

- `valhafin-db-credentials` — `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- `valhafin-backend-secrets` — `ENCRYPTION_KEY` (AES-256-GCM)

Voir le guide complet : [Sealed Secrets pour Valhafin](../valhafin-sealed-secrets.md)

## Network Policy

Une NetworkPolicy restreint l'accès à PostgreSQL : seul le pod backend peut communiquer avec la base de données.

## Ordre de déploiement (sync-waves internes)

1. SealedSecrets (wave -1)
2. Database / StatefulSet (wave 0)
3. Backend / Deployment (wave 1)
4. Frontend / Deployment (wave 2)
5. Ingress (wave 3)

## Fichiers

- Manifest ArgoCD : [`argocd-apps/valhafin-app.yml`](../argocd-apps/valhafin-app.yml)
- Chart Helm : [`helm/valhafin/`](../helm/valhafin/)
- Code source : [github.com/Thybaau/valhafin](https://github.com/thybaau/valhafin)
