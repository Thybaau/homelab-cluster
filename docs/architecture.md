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
         ├── traefik-tls-app.yml      (sync-wave: -2)
         ├── metallb-app.yml          (sync-wave: 0)
         ├── sealed-secrets-app.yml   (sync-wave: 0)
         ├── homepage-app.yml         (sync-wave: 1)
         ├── prometheus-stack-app.yml (sync-wave: 1)
         ├── valhafin-app.yml         (sync-wave: 1)
         ├── cloudflare-app.yml       (sync-wave: 3)
         └── adguard-home-app.yml     (sync-wave: 5)
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
| `valhafin` | ✅ Ingress | Traefik → backend:8080, Traefik → frontend:80, backend → database:5432 |
| `homepage` | ✅ Ingress | Traefik → homepage:3000 |
| `networking` | ✅ Ingress | Prometheus → cloudflared:2000 (métriques) |

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
│  monitoring (Prometheus)                                        │
│       └──→ networking/cloudflared:2000                          │
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
- `cloudflare-tunnel-token` — token du tunnel Cloudflare
- `homepage-proxmox` / `homepage-argocd` — credentials widgets Homepage
- `traefik-tls-cert` — certificat wildcard Cloudflare Origin CA (`*.caremelle.org`)

## Monitoring

Le stack de monitoring est basé sur **kube-prometheus-stack** :

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Prometheus  │────▶│  Grafana    │     │Alertmanager │
│ retention:7d│     │grafana.home │     │             │
│ storage:10Gi│     │ storage:2Gi │     │ storage:2Gi │
└─────────────┘     └─────────────┘     └─────────────┘
```

- Prometheus : rétention 7 jours, 10 Gi de stockage, limites CPU 300m / RAM 768Mi
- Grafana : accessible via `grafana.caremelle.org`, credentials via SealedSecret
- Alertmanager : activé avec 2 Gi de stockage

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
| kube-prometheus-stack | 65.1.1 |
| AdGuard Home | 0.3.25 (chart gabe565) |
| Cert-Manager | v1.13.3 (désactivé) |
