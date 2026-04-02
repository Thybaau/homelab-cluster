# Monitoring Stack (Prometheus + Grafana)

Stack de monitoring basé sur kube-prometheus-stack, déployant Prometheus, Grafana et Alertmanager.

## Rôle

Collecte de métriques du cluster et des applications, visualisation via Grafana, et alerting via Alertmanager.

## Configuration

| Paramètre | Valeur |
|---|---|
| Chart | `prometheus-community/kube-prometheus-stack` v65.1.1 + chart local |
| Namespace | `monitoring` |
| Sync wave | 1 |

## Composants

### Prometheus

| Paramètre | Valeur |
|---|---|
| Rétention | 7 jours |
| Taille max rétention | 8 GB |
| Stockage | 10 Gi (PVC) |
| CPU | 100m request / 300m limit |
| Mémoire | 256Mi request / 768Mi limit |

### Grafana

| Paramètre | Valeur |
|---|---|
| Accès | `grafana.home` / `grafana.caremelle.org` |
| Ingress | Traefik |
| Stockage | 2 Gi (persistence activée) |
| CPU limit | 150m |
| Mémoire limit | 256Mi |
| Credentials | SealedSecret `grafana-admin-credentials` |

### Alertmanager

| Paramètre | Valeur |
|---|---|
| Stockage | 2 Gi (PVC) |
| Mémoire limit | 64Mi |

## Architecture

L'application ArgoCD utilise deux sources :
1. Le chart officiel `kube-prometheus-stack` avec les values inline (Prometheus, Grafana, Alertmanager)
2. Le chart local `helm/prometheus-stack/` qui déploie le SealedSecret des credentials Grafana

## Secrets

Le mot de passe admin Grafana est stocké dans un SealedSecret `grafana-admin-credentials` (clés : `admin-user`, `admin-password`), référencé via `grafana.admin.existingSecret`.

## Accès

```bash
# Via le domaine local
http://grafana.home

# Via le domaine public (Cloudflare Tunnel)
http://grafana.caremelle.org
```

## Fichiers

- Manifest ArgoCD : [`argocd-apps/prometheus-stack-app.yml`](../argocd-apps/prometheus-stack-app.yml)
- Chart Helm local : [`helm/prometheus-stack/`](../helm/prometheus-stack/)
  - `templates/grafana-admin-sealedsecret.yaml` — SealedSecret credentials Grafana
