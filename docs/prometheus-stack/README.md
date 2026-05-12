# Monitoring Stack (Prometheus + Grafana + Alertmanager + Loki + Alloy)

Stack d'observabilité complet basé sur kube-prometheus-stack, enrichi de composants pour les logs centralisés, l'alerting Discord, les dashboards config-as-code, et le monitoring des services.

## Rôle

- Collecte de métriques du cluster et des applications (Prometheus)
- Collecte et stockage centralisé des logs (Alloy + Loki)
- Visualisation via Grafana (4 dashboards custom provisionnés automatiquement)
- Alerting vers Discord (Alertmanager, 2 canaux par sévérité)
- Monitoring de la disponibilité des services (blackbox-exporter)
- Métriques PostgreSQL de la base Valhafin (postgres-exporter)

## Composants et configuration

### kube-prometheus-stack (prometheus-stack-app.yml)

| Paramètre | Valeur |
|---|---|
| Chart | `prometheus-community/kube-prometheus-stack` v72.6.2 + chart local |
| Namespace | `monitoring` |
| Sync wave | 1 |
| Pattern | Values inline dans ArgoCD Application + chart wrapper local pour templates |

#### Prometheus

| Paramètre | Valeur |
|---|---|
| Rétention | 7 jours |
| Stockage | 10 Gi (PVC) |

#### Grafana

| Paramètre | Valeur |
|---|---|
| Accès | `grafana.caremelle.org` |
| Ingress | Traefik (HTTPS) |
| Stockage | 2 Gi (persistence activée) |
| Credentials | SealedSecret `grafana-admin-credentials` |
| Datasources | Prometheus (défaut) + Loki (uid: loki) |
| Dashboards | Provisionnés via sidecar ConfigMap (config-as-code) |

#### Alertmanager

| Paramètre | Valeur |
|---|---|
| Stockage | 2 Gi (PVC) |
| Mémoire limit | 64Mi |
| Receivers | `discord-critical`, `discord-monitoring` |
| Secrets | SealedSecret `discord-webhook-urls` monté via `alertmanagerSpec.secrets` |
| Routing | severity:critical → discord-critical (repeat 1h), severity:warning → discord-monitoring (repeat 4h) |
| Grouping | alertname + namespace, group_wait 30s, group_interval 5m |
| Templates | Emojis 🚨/⚠️/✅, lien dashboard_url, summary en français |
| Inhibit rules | critical supprime warning (même alertname+namespace), StorageCritical supprime StorageWarning (même instance) |

### Loki (loki-app.yml)

| Paramètre | Valeur |
|---|---|
| Chart | `grafana-community/loki` v13.1.3 (appVersion 3.7.1) |
| Namespace | `monitoring` |
| Sync wave | 2 |
| Mode | Monolithic (1 replica) |
| Stockage | PVC 10 Gi (filesystem) |
| Rétention | 168h (7 jours), compactor activé |
| Auth | Désactivé (pas de multi-tenancy) |
| Replication factor | 1 |
| RAM | 256Mi request / 512Mi limit |
| CPU | 100m request / 200m limit |
| Accès | `loki.monitoring.svc:3100` (interne uniquement) |

### Alloy (alloy-app.yml)

| Paramètre | Valeur |
|---|---|
| Chart | `grafana/alloy` v1.7.0 (appVersion v1.15.0) |
| Namespace | `monitoring` |
| Sync wave | 3 |
| Mode | DaemonSet (1 pod par nœud) |
| Collecte | Filesystem `/var/log/pods/` (montage varlog) |
| Parsing | CRI (containerd k3s) via `stage.cri {}` |
| Labels | namespace, pod, container, node |
| Destination | `http://loki.monitoring.svc:3100/loki/api/v1/push` |
| RAM | 128Mi request / 256Mi limit par nœud |
| CPU | 50m request / 100m limit par nœud |

### blackbox-exporter (blackbox-exporter-app.yml)

| Paramètre | Valeur |
|---|---|
| Chart | `prometheus-community/prometheus-blackbox-exporter` v11.9.1 |
| Namespace | `monitoring` |
| Sync wave | 4 |
| Module | `http_2xx` (prober HTTP, timeout 5s) |
| Cibles | `valhafin-backend.valhafin.svc:8080/health`, `homepage.homepage.svc:3000` |
| Interval | 60s |
| RAM | 32Mi request / 64Mi limit |
| CPU | 10m request / 50m limit |
| ServiceMonitor | label `release: monitoring-stack` |

### postgres-exporter (postgres-exporter-app.yml)

| Paramètre | Valeur |
|---|---|
| Chart | `prometheus-community/prometheus-postgres-exporter` v7.5.2 |
| Namespace | `monitoring` |
| Sync wave | 4 |
| Endpoint DB | `valhafin-database.valhafin.svc:5432` |
| Credentials | SealedSecret `postgres-exporter-credentials` (DSN complet) |
| SSL | Désactivé (intra-cluster) |
| Métriques | pg_stat_activity, pg_database_size_bytes, pg_stat_user_tables, pg_locks |
| RAM | 32Mi request / 64Mi limit |
| CPU | 10m request / 30m limit |
| ServiceMonitor | label `release: monitoring-stack` |

## Règles d'alerting (PrometheusRules)

Configurées dans `additionalPrometheusRulesMap` des values inline de `prometheus-stack-app.yml` :

| Groupe | Alerte | Sévérité | Condition | Dashboard |
|---|---|---|---|---|
| homelab-infrastructure | StorageWarning | warning | Disque VM > 80% (10m) | /d/storage |
| homelab-infrastructure | StorageCritical | critical | Disque VM > 90% (5m) | /d/storage |
| homelab-infrastructure | NodeNotReady | critical | Nœud NotReady (3m) | /d/cluster-overview |
| homelab-infrastructure | PodCrashLooping | critical | > 3 restarts en 15m | /d/cluster-overview |
| homelab-infrastructure | PodHighMemoryUsage | warning | RAM > 85% limit (10m) | /d/cluster-overview |
| homelab-infrastructure | PodHighCpuUsage | warning | CPU > 90% limit (10m) | /d/cluster-overview |
| homelab-services | ServiceDown | critical | probe_success == 0 (5m) | /d/cluster-overview |
| homelab-alerting-health | AlertmanagerFailedNotifications | critical | Échecs > 1 en 15m | /d/cluster-overview |

## Dashboards Grafana

Provisionnés automatiquement via le mécanisme sidecar ConfigMap :

1. Fichiers JSON dans `helm/prometheus-stack/dashboards/`
2. Template `dashboards-configmaps.yaml` génère un ConfigMap par fichier
3. Label `grafana_dashboard: "1"` → sidecar détecte et charge

| Dashboard | UID | Datasource | Description |
|---|---|---|---|
| Cluster Overview | `cluster-overview` | Prometheus | Santé nœuds, CPU/RAM, probes, PostgreSQL |
| Stockage | `storage` | Prometheus | Disque VMs, PVCs, top consommateurs |
| Réseau | `network` | Prometheus | Trafic nœud/pod, Traefik, latence |
| Logs | `logs` | Loki | Logs filtrables par namespace/pod/recherche |

Pour ajouter un dashboard : créer un fichier `<nom>-dashboard.json` dans `helm/prometheus-stack/dashboards/` et pousser sur Git.

## Architecture ArgoCD

Le prometheus-stack utilise un pattern **hybride** :
- **Source 1** : chart upstream `kube-prometheus-stack` avec **values inline** (Alertmanager config, PrometheusRules, datasources, resources)
- **Source 2** : chart local `helm/prometheus-stack/` qui déploie les **templates** (SealedSecrets, ConfigMaps dashboards, PodMonitor Traefik)

Les autres composants (Loki, Alloy, blackbox-exporter, postgres-exporter) utilisent le pattern **multi-sources standard** :
- Source 1 : chart upstream (version fixée)
- Source 2 : ref Git vers `helm/<nom>/values.yaml`

## Secrets

| Secret | Namespace | Contenu | Utilisé par |
|---|---|---|---|
| `grafana-admin-credentials` | monitoring | admin-user, admin-password | Grafana |
| `discord-webhook-urls` | monitoring | discord-critical-webhook-url, discord-monitoring-webhook-url | Alertmanager (url_file) |
| `postgres-exporter-credentials` | monitoring | DATA_SOURCE_NAME (DSN complet) | postgres-exporter |

Commandes kubeseal :
```bash
# Webhooks Discord
echo -n "https://discord.com/api/webhooks/<id>/<token>/slack" | \
  kubeseal --raw --namespace monitoring --name discord-webhook-urls --from-file=/dev/stdin

# Credentials PostgreSQL
echo -n "postgresql://USER:PASSWORD@valhafin-database.valhafin.svc:5432/DATABASE?sslmode=disable" | \
  kubectl create secret generic postgres-exporter-credentials \
    --namespace=monitoring --from-file=DATA_SOURCE_NAME=/dev/stdin \
    --dry-run=client -o yaml | kubeseal --controller-namespace kube-system --format yaml
```

## Fichiers

```
argocd-apps/
├── prometheus-stack-app.yml       # Values inline (Alertmanager, PrometheusRules, datasources)
├── loki-app.yml                   # Chart grafana-community v13.1.3
├── alloy-app.yml                  # Chart grafana v1.7.0
├── blackbox-exporter-app.yml      # Chart prometheus-community v11.9.1
└── postgres-exporter-app.yml      # Chart prometheus-community v7.5.2

helm/
├── prometheus-stack/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── dashboards/
│   │   ├── cluster-overview-dashboard.json
│   │   ├── storage-dashboard.json
│   │   ├── network-dashboard.json
│   │   └── logs-dashboard.json
│   └── templates/
│       ├── grafana-admin-sealedsecret.yaml
│       ├── discord-webhook-sealedsecret.yaml
│       ├── postgres-credentials-sealedsecret.yaml
│       ├── dashboards-configmaps.yaml
│       └── traefik-podmonitor.yaml
├── loki/
│   ├── Chart.yaml
│   └── values.yaml
├── alloy/
│   ├── Chart.yaml
│   └── values.yaml
├── blackbox-exporter/
│   ├── Chart.yaml
│   └── values.yaml
└── postgres-exporter/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        └── postgres-credentials-sealedsecret.yaml
```

## NetworkPolicies (monitoring → services)

Les probes et exporters nécessitent des NetworkPolicies pour accéder aux services dans les namespaces avec default-deny :

| NetworkPolicy | Namespace | Flux autorisé |
|---|---|---|
| `valhafin-allow-probes` | valhafin | monitoring → backend:8080 |
| `valhafin-allow-postgres-exporter` | valhafin | monitoring → database:5432 |
| `homepage-allow-probes` | homepage | monitoring → homepage:3000 |
| `cloudflare-allow-probes` | networking | monitoring → cloudflared:2000 |
