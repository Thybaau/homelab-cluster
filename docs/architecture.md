# Architecture du Cluster

Ce document décrit l'architecture technique du cluster k3s homelab, les composants déployés, et les flux de communication entre eux.

## Vue d'ensemble

Le cluster k3s est déployé sur des VMs Proxmox provisionnées par Terraform ([homelab-infra-iac](https://github.com/Thybaau/homelab-infra-iac)). Ansible orchestre l'installation de k3s et des outils GitOps. ArgoCD gère ensuite le déploiement continu de toutes les applications.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Proxmox VE 9.1.5                            │
│                        (192.168.1.200:8006)                         │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ k3s-master   │  │k3s-worker-01 │  │k3s-worker-0N │              │
│  │ .102         │  │ .103         │  │ .10X         │              │
│  │              │  │              │  │              │              │
│  │ k3s server   │  │ k3s agent    │  │ k3s agent    │              │
│  │ API :6443    │  │              │  │              │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         └─────────────────┴─────────────────┘                       │
│                    Réseau 192.168.1.0/24                             │
└─────────────────────────────────────────────────────────────────────┘
```

## Couches d'infrastructure

### 1. Provisionnement (Terraform)

Les VMs sont créées sur Proxmox via Terraform avec cloud-init (Ubuntu 24.04). Les ressources sont validées par des contraintes matérielles (RAM ≤ 12 Go, stockage ≤ 105 Go).

### 2. Configuration (Ansible)

Le playbook Ansible exécute 5 étapes séquentielles :

```
prepare_nodes → k3s_master → k3s_workers → gitops_tools → verify_cluster
     │               │             │              │              │
  Paquets,       k3s server,   k3s agent,    kubectl,      Vérification
  firewall,      kubeconfig,   join token    helm,         nœuds, pods,
  sysctl,        token         serial: 1     helmfile,     services
  modules                                    ArgoCD
```

Chaque étape est taggée et peut être exécutée indépendamment.

### 3. Infrastructure de base (Helmfile)

Helmfile déploie les composants fondamentaux directement sur le master :

| Composant | Version | Statut | Rôle |
|---|---|---|---|
| ArgoCD | 5.51.6 | Activé | GitOps CD — synchronise `argocd-apps/` |
| Cert-Manager | v1.13.3 | Désactivé | Gestion certificats TLS (futur) |

### 4. Applications (ArgoCD)

ArgoCD utilise le pattern **App-of-Apps** : une `root-app` pointe vers le dossier `argocd-apps/` et synchronise automatiquement tout manifest YAML ajouté.

```
root-app.yml
    │
    └── argocd-apps/
         ├── traefik-tls-app.yml          (sync-wave: -2)
         ├── metallb-app.yml              (sync-wave: 0)
         ├── sealed-secrets-app.yml       (sync-wave: 0)
         ├── homepage-app.yml             (sync-wave: 1)
         ├── prometheus-stack-app.yml     (sync-wave: 1)
         ├── valhafin-app.yml             (sync-wave: 1)
         ├── cloudflare-app.yml           (sync-wave: 1)
         ├── loki-app.yml                 (sync-wave: 2)
         ├── alloy-app.yml                (sync-wave: 3)
         ├── blackbox-exporter-app.yml    (sync-wave: 4)
         ├── postgres-exporter-app.yml    (sync-wave: 4)
         └── adguard-home-app.yml         (sync-wave: 5)
```

Les `sync-wave` contrôlent l'ordre de déploiement : TLS cert d'abord (wave -2), puis MetalLB et Sealed Secrets (wave 0), puis les applications (wave 1+), et enfin le DNS (wave 5).

Toutes les applications sont configurées avec :
- `automated.prune: true` — supprime les ressources orphelines
- `automated.selfHeal: true` — restaure l'état Git si modifié manuellement
- `retry` avec backoff exponentiel (5 tentatives max)

## Architecture réseau

```
Internet
    │
    ▼
┌──────────────────┐
│ Cloudflare Tunnel│  *.caremelle.org
└────────┬─────────┘
         │
         ▼
┌──────────────────┐     ┌──────────────────┐
│    Traefik       │◄────│    MetalLB        │
│  (Ingress)       │     │  192.168.1.151    │
│  192.168.1.151   │     │  (L2 mode)        │
│  HTTPS (443)     │     └──────────────────┘
│  HTTP→HTTPS redir│
└────────┬─────────┘
         │
    ┌────┴──────────────────────────┐
    │    Routage par host (HTTPS)   │
    ├───────────────────────────────┤
    │ valhafin.caremelle.org → backend  │
    │ homepage.caremelle.org → homepage │
    │ grafana.caremelle.org  → grafana  │
    │ adguard.caremelle.org  → adguard  │
    └───────────────────────────────┘

┌──────────────────┐
│  AdGuard Home    │  DNS local
│  192.168.1.152   │  *.caremelle.org → 192.168.1.151
│  (LoadBalancer)  │  Upstream: Quad9 + Cloudflare DoH
└──────────────────┘
```

### TLS

Traefik sert un certificat wildcard Cloudflare Origin CA (`*.caremelle.org`) via un TLSStore default. Le certificat est stocké dans un SealedSecret (`traefik-tls-cert` dans `kube-system`), déployé par ArgoCD via le chart `traefik-tls` (sync-wave -2, avant toutes les applications).

- Entrypoint `web` (80) : redirection permanente vers HTTPS
- Entrypoint `websecure` (443) : TLS activé avec le certificat Origin CA
- Tous les ingress utilisent l'entrypoint `websecure`

### Plages IP

| Plage | Usage |
|---|---|
| `192.168.1.102` | Master k3s (API server) |
| `192.168.1.103+` | Workers k3s |
| `192.168.1.151` | Traefik (Ingress via MetalLB) |
| `192.168.1.152` | AdGuard Home DNS (via MetalLB) |
| `192.168.1.151-170` | Pool MetalLB disponible |
| `192.168.1.200` | Proxmox VE |

### Domaines

| Domaine | Résolution | Cible |
|---|---|---|
| `*.caremelle.org` (local) | AdGuard DNS rewrites | `192.168.1.151` (Traefik, HTTPS) |
| `*.caremelle.org` (internet) | Cloudflare Tunnel | Services internes (homepage uniquement) |

## Sécurité réseau (NetworkPolicies)

Les namespaces gérés par les charts custom appliquent une politique **default-deny ingress** : tout trafic entrant est bloqué par défaut, puis des règles explicites autorisent uniquement les flux légitimes.

### Politique par namespace

| Namespace | Default Deny | Règles Allow |
|---|---|---|
| `valhafin` | ✅ Ingress | Traefik → backend:8080, Traefik → frontend:80, backend → database:5432, monitoring → backend:8080 (probes), monitoring → database:5432 (postgres-exporter) |
| `homepage` | ✅ Ingress | Traefik → homepage:3000, monitoring → homepage:3000 (probes) |
| `networking` | ✅ Ingress | Prometheus → cloudflared:2000 (métriques), monitoring → cloudflared:2000 (probes) |

### Namespaces non couverts

| Namespace | Raison |
|---|---|
| `monitoring` | Géré par kube-prometheus-stack — flux internes complexes |
| `metallb-system` | Géré par le chart officiel MetalLB — communication L2/ARP |
| `sealed-secrets` | Chart externe — communication via kube-apiserver |
| `argocd` | Géré par Helmfile — flux internes complexes |

### Notes

- Toutes les policies sont conditionnées par `networkPolicy.enabled` dans les `values.yaml` de chaque chart, désactivables individuellement.
- Les sélecteurs de namespace utilisent le label automatique `kubernetes.io/metadata.name`.
- AdGuard Home (`networking`) utilise `hostNetwork: true` — les NetworkPolicies ne s'appliquent pas aux pods en hostNetwork avec Flannel (CNI k3s).
- Seul le trafic **ingress** est restreint. Les policies egress ne sont pas implémentées.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flux autorisés (ingress)                      │
│                                                                 │
│  kube-system (Traefik)                                          │
│       │                                                         │
│       ├──→ valhafin/backend:8080                                │
│       ├──→ valhafin/frontend:80                                 │
│       └──→ homepage/homepage:3000                               │
│                                                                 │
│  valhafin/backend                                               │
│       └──→ valhafin/database:5432                               │
│                                                                 │
│  monitoring (Prometheus, blackbox-exporter, postgres-exporter)   │
│       ├──→ valhafin/backend:8080      (probes HTTP)             │
│       ├──→ valhafin/database:5432     (métriques PostgreSQL)    │
│       ├──→ homepage/homepage:3000     (probes HTTP)             │
│       └──→ networking/cloudflared:2000 (métriques)              │
│                                                                 │
│  Tout autre trafic ingress → ❌ BLOQUÉ (default-deny)           │
└─────────────────────────────────────────────────────────────────┘
```

## Sécurité des pods (Security Contexts)

Tous les pods des charts custom appliquent des `securityContext` pod-level et container-level :

| Composant | runAsNonRoot | readOnlyRootFilesystem | capabilities |
|---|---|---|---|
| Valhafin backend | ✅ (UID 1000) | ✅ | drop ALL |
| Valhafin frontend | ❌ (nginx standard) | ❌ (écrit /var/cache) | drop ALL + add NET_BIND_SERVICE, SETUID, SETGID |
| Valhafin database | ✅ (UID 999) | ❌ (écrit PGDATA) | drop ALL + add CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID |
| Cloudflared | ✅ (UID 65532) | ✅ | drop ALL |
| Homepage | ✅ (UID 1000) | ❌ (écrit /app/config) | drop ALL |

- `allowPrivilegeEscalation: false` sur tous les conteneurs sans exception
- Tous les securityContext sont paramétrables via `values.yaml`

## Gestion des secrets

Tous les secrets sont chiffrés via **Sealed Secrets** avant d'être stockés dans Git :

```
Secret en clair → kubeseal (clé publique) → SealedSecret (Git-safe)
                                                    │
                                              ArgoCD sync
                                                    │
                                            Sealed Secrets Controller
                                            (déchiffre avec clé privée)
                                                    │
                                              Secret Kubernetes
```

Secrets gérés :
- `valhafin-db-credentials` — credentials PostgreSQL
- `valhafin-backend-secrets` — clé de chiffrement AES-256
- `grafana-admin-credentials` — mot de passe admin Grafana
- `discord-webhook-urls` — webhooks Discord pour Alertmanager (critical + monitoring)
- `postgres-exporter-credentials` — DSN PostgreSQL pour postgres-exporter
- `cloudflare-tunnel-token` — token du tunnel Cloudflare
- `homepage-proxmox` / `homepage-argocd` — credentials widgets Homepage
- `traefik-tls-cert` — certificat wildcard Cloudflare Origin CA (`*.caremelle.org`)

## Monitoring

Le stack d'observabilité est basé sur **kube-prometheus-stack** enrichi de composants complémentaires pour les logs, l'alerting et le monitoring des services.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        OBSERVABILITÉ                                │
│                                                                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │  Prometheus  │    │     Loki     │    │      Grafana         │  │
│  │  (métriques) │    │   (logs)     │    │   (visualisation)    │  │
│  │  retention:7d│    │  rétention:7j│    │  grafana.caremelle.org│ │
│  │  storage:10Gi│    │  storage:10Gi│    │  storage:2Gi         │  │
│  └──────┬───────┘    └──────▲───────┘    └──────────────────────┘  │
│         │                   │                       ▲               │
│         │            ┌──────┴───────┐          Dashboards          │
│         │            │    Alloy     │          config-as-code       │
│         │            │ (DaemonSet)  │          (4 JSON + sidecar)   │
│         │            │ /var/log/pods│                               │
│         │            └──────────────┘                               │
│         ▼                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │ Alertmanager │    │  blackbox-   │    │  postgres-exporter   │  │
│  │  → Discord   │    │  exporter    │    │  (métriques PG)      │  │
│  │ 🚨 critiques │    │ (probes HTTP)│    │  valhafin-database   │  │
│  │ ⚠️ warnings  │    └──────────────┘    └──────────────────────┘  │
│  └──────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

### Composants

| Composant | Version chart | Mode | Ressources |
|---|---|---|---|
| kube-prometheus-stack | 72.6.2 | Inline values ArgoCD | Prometheus 10Gi, Grafana 2Gi, Alertmanager 2Gi |
| Loki | 13.1.3 (grafana-community) | Monolithic, 1 replica | 256Mi/512Mi RAM, PVC 10Gi |
| Alloy | 1.7.0 (grafana) | DaemonSet (1 pod/nœud) | 128Mi/256Mi RAM par nœud |
| blackbox-exporter | 11.9.1 (prometheus-community) | Deployment | 32Mi/64Mi RAM |
| postgres-exporter | 7.5.2 (prometheus-community) | Deployment | 32Mi/64Mi RAM |

### Alerting (Alertmanager → Discord)

Alertmanager route les alertes vers 2 canaux Discord :
- **#alertes-critiques** : severity critical (repeat 1h)
- **#alertes-monitoring** : severity warning (repeat 4h) + watchdog heartbeat

Configuration :
- Webhooks Discord via SealedSecret `discord-webhook-urls` + `url_file` (jamais en clair)
- Grouping : `alertname` + `namespace`, group_wait 30s, group_interval 5m
- Templates : emojis 🚨/⚠️/✅, lien `dashboard_url`, summary en français
- Inhibit rules : critical supprime warning (même alertname+namespace), StorageCritical supprime StorageWarning (même instance)

### Règles d'alerting (PrometheusRules)

Configurées dans `additionalPrometheusRulesMap` des values inline :

| Groupe | Alerte | Sévérité | Condition |
|---|---|---|---|
| homelab-infrastructure | StorageWarning | warning | Disque VM > 80% pendant 10m |
| homelab-infrastructure | StorageCritical | critical | Disque VM > 90% pendant 5m |
| homelab-infrastructure | NodeNotReady | critical | Nœud NotReady pendant 3m |
| homelab-infrastructure | PodCrashLooping | critical | > 3 restarts en 15m |
| homelab-infrastructure | PodHighMemoryUsage | warning | RAM pod > 85% limit pendant 10m |
| homelab-infrastructure | PodHighCpuUsage | warning | CPU pod > 90% limit pendant 10m |
| homelab-services | ServiceDown | critical | probe_success == 0 pendant 5m |
| homelab-alerting-health | AlertmanagerFailedNotifications | critical | Échecs d'envoi > 1 en 15m |

### Logs centralisés (Loki + Alloy)

Pipeline de collecte :
```
Pods (stdout/stderr) → /var/log/pods/ → Alloy (DaemonSet)
    → discovery.kubernetes → relabel (namespace, pod, container, node)
    → local.file_match → loki.source.file → stage.cri {}
    → loki.write → http://loki.monitoring.svc:3100/loki/api/v1/push
```

- Loki : mode Monolithic, auth disabled, replication_factor 1, rétention 168h (compactor)
- Alloy : collecte filesystem `/var/log/pods/`, parsing CRI (containerd k3s)
- Datasource Loki configurée dans Grafana (`uid: loki`)

### Dashboards Grafana (config-as-code)

Mécanisme de provisionnement :
1. Fichiers JSON dans `helm/prometheus-stack/dashboards/`
2. Template Helm `dashboards-configmaps.yaml` génère un ConfigMap par fichier (`.Files.Glob`)
3. Label `grafana_dashboard: "1"` → sidecar Grafana détecte et charge automatiquement
4. Survie à la perte du PVC Grafana

| Dashboard | UID | Datasource | Description |
|---|---|---|---|
| Cluster Overview | `cluster-overview` | Prometheus | Santé nœuds, CPU/RAM par nœud/namespace/pod, probes, PostgreSQL |
| Stockage | `storage` | Prometheus | Utilisation disque VMs, PVCs, top consommateurs |
| Réseau | `network` | Prometheus | Trafic par nœud/pod, ingress Traefik, latence par service |
| Logs | `logs` | Loki | Logs centralisés filtrables par namespace/pod avec recherche |

### Monitoring des services

- **blackbox-exporter** : probes HTTP sur `valhafin-backend.valhafin.svc:8080/health` et `homepage.homepage.svc:3000` (interval 60s)
- **postgres-exporter** : métriques PostgreSQL via `valhafin-database.valhafin.svc:5432` (connexions, taille base, requêtes)
- **PodMonitor Traefik** : scraping des métriques Traefik (requêtes, latence, codes réponse) sur le port 9100
- ServiceMonitors avec label `release: monitoring-stack` pour la découverte Prometheus

## CI/CD

```
Push / PR sur main
       │
       ├── deploy.yml (self-hosted runner)
       │     └── ansible-playbook → cluster
       │
       └── security-audit.yml (ubuntu-latest)
             └── Scan : passwords, tokens, clés, vault, variables
```

Le workflow de déploiement utilise un runner self-hosted (accès réseau local requis). L'audit de sécurité tourne aussi en planifié chaque lundi à 2h.

## Versions des composants

| Composant | Version |
|---|---|
| k3s | v1.34.4+k3s1 |
| Ubuntu | 24.04 |
| ArgoCD | 5.51.6 |
| Helmfile | v0.163.1 |
| MetalLB | 0.14.9 |
| Sealed Secrets | 2.13.2 |
| kube-prometheus-stack | 72.6.2 |
| Loki | 3.7.1 (chart 13.1.3) |
| Alloy | v1.15.0 (chart 1.7.0) |
| blackbox-exporter | chart 11.9.1 |
| postgres-exporter | chart 7.5.2 |
| AdGuard Home | 0.3.25 (chart gabe565) |
| Cert-Manager | v1.13.3 (désactivé) |
