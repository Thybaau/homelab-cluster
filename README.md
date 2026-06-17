# homelab-cluster

[![Deploy k3s Cluster](https://github.com/Thybaau/homelab-cluster/actions/workflows/deploy.yml/badge.svg)](https://github.com/Thybaau/homelab-cluster/actions/workflows/deploy.yml)
[![Security Audit](https://github.com/Thybaau/homelab-cluster/actions/workflows/security-audit.yml/badge.svg)](https://github.com/Thybaau/homelab-cluster/actions/workflows/security-audit.yml)

![k3s](https://img.shields.io/badge/k3s-stable_channel-blue?logo=k3s&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?logo=ubuntu&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-8.x-EE0000?logo=ansible&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-v3-0F1689?logo=helm&logoColor=white)
![Helmfile](https://img.shields.io/badge/Helmfile-v0.163.1-0F1689?logo=helm&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-9.5.21-EF7B4D?logo=argo&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-72.9.1-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Loki_13.7.2-F46800?logo=grafana&logoColor=white)
![MetalLB](https://img.shields.io/badge/MetalLB-0.16.1-blue)
![Sealed Secrets](https://img.shields.io/badge/Sealed_Secrets-2.13.2-326CE5?logo=kubernetes&logoColor=white)
![Kured](https://img.shields.io/badge/Kured-5.6.0-blue)

Déploiement automatisé d'un cluster k3s sur des VMs Ubuntu 24.04 hébergées sur Proxmox, avec orchestration Ansible, gestion GitOps via ArgoCD, et services d'infrastructure déployés par Helm.

Le cluster intègre une stack d'observabilité complète : métriques (Prometheus), logs centralisés (Loki + Alloy), alerting Discord (Alertmanager), dashboards custom (Grafana config-as-code), et monitoring des services (blackbox-exporter, postgres-exporter).

Les mises à jour du cluster sont automatisées : k3s se met à jour via le System Upgrade Controller (channel stable), et les nœuds redémarrent automatiquement après les mises à jour OS grâce à Kured.

## Sommaire

- [Vue d'ensemble](#vue-densemble)
- [Prérequis](#prérequis)
- [Applications déployées](#applications-déployées)
- [Structure du projet](#structure-du-projet)
- [Déploiement](#déploiement)
- [Réseau](#réseau)
- [Observabilité](#observabilité)
- [CI/CD](#cicd)
- [Documentation](#documentation)

## Vue d'ensemble

Ce projet gère l'intégralité du cycle de vie d'un cluster Kubernetes k3s :

- **Provisionnement** : Ansible prépare les nœuds, installe k3s (1 master + N workers), et déploie les outils GitOps
- **Infrastructure** : Helmfile déploie les composants fondamentaux (ArgoCD, Cert-Manager)
- **Applications** : ArgoCD synchronise automatiquement les applications depuis les manifests dans `argocd-apps/`
- **Charts custom** : Helm charts locaux dans `helm/` pour les services du cluster
- **CI/CD** : GitHub Actions orchestre le déploiement Ansible et l'audit de sécurité automatiquement


```
┌──────────────────────────────────────────────────────────────────┐
│                    Machine de Contrôle Ansible                   │
│                      (ou GitHub Runner)                          │
└──────────────────────┬───────────────────────────────────────────┘
                       │ SSH
          ┌────────────┼────────────────┐
          │            │                │
     ┌────▼────┐  ┌───▼──────┐   ┌────▼──────┐
     │ Master  │  │Worker-01 │   │Worker-0N  │
     │ :6443   │  │          │   │           │
     └────┬────┘  └────┬─────┘   └────┬──────┘
          │            │              │
          └────────────┴──────────────┘
                k3s Cluster Network
                       │
          ┌────────────┼────────────────┐
          │            │                │
     Helmfile     ArgoCD Root      Helm Charts
     (ArgoCD,     App (sync        (metallb,
     Cert-Mgr)    argocd-apps/)    valhafin, ...)
```

## Prérequis

- VMs Ubuntu 24.04 provisionnées (via [homelab-infra-iac](https://github.com/Thybaau/homelab-infra-iac))
- Accès SSH avec l'utilisateur `k3s` sur tous les nœuds
- Ansible 8.x (ansible-core 2.15+) installé localement
- Python : kubernetes, jmespath, netaddr, PyYAML

## Applications déployées

| Application | Namespace | Sync Wave | Source | Description |
|---|---|---|---|---|
| Traefik TLS | `kube-system` | -2 | Chart local | Configuration TLS pour l'ingress Traefik |
| [MetalLB](docs/metallb/) | `metallb-system` | 0 | Chart officiel v0.16.1 + config locale | Load balancer L2 (pool `192.168.1.151-170`) |
| [Sealed Secrets](docs/sealed-secrets/) | `sealed-secrets` | 0 | Chart Bitnami v2.13.2 | Chiffrement des secrets pour GitOps |
| Kured | `kube-system` | 0 | Chart kubereboot v5.6.0 | Reboot automatique des nœuds après mises à jour OS |
| System Upgrade Controller | `system-upgrade` | 0 | Chart local | Mises à jour automatiques de k3s (channel stable) |
| [Homepage](docs/homepage/) | `homepage` | 1 | Chart local | Dashboard homelab |
| [Monitoring Stack](docs/prometheus-stack/) | `monitoring` | 1 | kube-prometheus-stack v72.9.1 + local | Prometheus, Grafana, Alertmanager, dashboards |
| [Valhafin](docs/valhafin/) | `valhafin` | 1 | Chart local | App de gestion de portefeuille |
| Loki | `monitoring` | 2 | Chart grafana-community v13.7.2 | Backend de stockage de logs (mode Monolithic) |
| [Cloudflare](docs/cloudflare/) | `networking` | 3 | Chart local | Tunnel Cloudflare |
| Alloy | `monitoring` | 3 | Chart grafana v1.9.0 | Collecteur de logs DaemonSet (filesystem → Loki) |
| blackbox-exporter | `monitoring` | 4 | Chart prometheus-community v11.11.0 | Probes HTTP disponibilité services |
| postgres-exporter | `monitoring` | 4 | Chart prometheus-community v7.5.2 | Métriques PostgreSQL |
| [AdGuard Home](docs/adguard-home/) | `networking` | 5 | Chart gabe565 v0.3.25 | DNS local + ad-blocking |
| [Home Assistant](docs/home-assistant/) | `home-assistant` | 5 | Chart pajikos v0.3.66 | Domotique et automation |

## Structure du projet

```
.
├── ansible/                    # Automatisation Ansible
│   ├── inventory.ini           # Inventaire des hôtes
│   ├── playbook.yml            # Playbook principal
│   ├── ansible.cfg             # Configuration Ansible
│   ├── group_vars/             # Variables (all.yml, k3s_cluster.yml)
│   └── roles/                  # Rôles Ansible
│       ├── prepare_nodes/      # Préparation système (paquets, firewall, sysctl)
│       ├── k3s_master/         # Installation k3s server
│       ├── k3s_workers/        # Jonction des workers au cluster
│       ├── gitops_tools/       # kubectl, helm, helmfile sur le master
│       └── verify_cluster/     # Vérification post-déploiement
├── argocd-apps/                # Manifests ArgoCD Application
│   ├── adguard-home-app.yml    # DNS + ad-blocking
│   ├── alloy-app.yml           # Collecteur de logs DaemonSet
│   ├── blackbox-exporter-app.yml # Probes HTTP services
│   ├── cloudflare-app.yml      # Cloudflare Tunnel
│   ├── home-assistant-app.yml  # Domotique et automation
│   ├── homepage-app.yml        # Dashboard homelab
│   ├── kured-app.yml           # Reboot automatique post-update
│   ├── loki-app.yml            # Backend de stockage de logs
│   ├── metallb-app.yml         # Load balancer L2
│   ├── postgres-exporter-app.yml # Métriques PostgreSQL
│   ├── prometheus-stack-app.yml# Monitoring (Prometheus + Grafana + Alertmanager)
│   ├── sealed-secrets-app.yml  # Gestion des secrets chiffrés
│   ├── system-upgrade-controller-app.yml # Mises à jour k3s automatiques
│   ├── traefik-tls-app.yml     # Configuration TLS Traefik
│   └── valhafin-app.yml        # Application financière
├── helm/                       # Charts Helm custom
│   ├── alloy/                  # Collecteur de logs (pipeline River, DaemonSet)
│   ├── blackbox-exporter/      # Probes HTTP (valhafin, homepage)
│   ├── cloudflare/             # Cloudflared tunnel
│   ├── home-assistant/         # Domotique (Home Assistant)
│   ├── homepage/               # Dashboard homepage.dev
│   ├── kured/                  # Reboot automatique post-update OS
│   ├── loki/                   # Backend logs (Monolithic, PVC 10Gi, rétention 7j)
│   ├── metallb/                # Config MetalLB (IP pool + L2)
│   ├── postgres-exporter/      # Métriques PostgreSQL + SealedSecret
│   ├── prometheus-stack/       # Dashboards JSON, SealedSecrets, PodMonitor Traefik
│   ├── system-upgrade-controller/ # SUC + Plans de mise à jour k3s
│   ├── traefik-tls/            # Certificats TLS pour l'ingress Traefik
│   └── valhafin/               # App complète (backend + frontend + DB)
├── helmfile.yaml               # Infrastructure de base (ArgoCD, Cert-Manager)
├── root-app.yml                # ArgoCD root Application (app-of-apps)
├── docs/                       # Documentation
└── scripts/                    # Scripts utilitaires
```

## Déploiement

### Déploiement complet

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

### Déploiement par étapes

```bash
ansible-playbook -i inventory.ini playbook.yml --tags prepare   # Préparer les nœuds
ansible-playbook -i inventory.ini playbook.yml --tags master    # Installer le master
ansible-playbook -i inventory.ini playbook.yml --tags workers   # Joindre les workers
ansible-playbook -i inventory.ini playbook.yml --tags gitops    # Outils GitOps + Helmfile
ansible-playbook -i inventory.ini playbook.yml --tags verify    # Vérifier le cluster
```

### Récupérer le kubeconfig

```bash
ssh k3s@192.168.1.102 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed 's/127.0.0.1/192.168.1.102/g' > ~/.kube/k3s-config
chmod 600 ~/.kube/k3s-config
export KUBECONFIG=~/.kube/k3s-config
```

## Réseau

- Master API : `192.168.1.102:6443`
- MetalLB IP pool : `192.168.1.151-170`
- Traefik (Ingress) : `192.168.1.151`
- AdGuard DNS : `192.168.1.152`
- Domaines locaux : `*.home` (via AdGuard DNS rewrites)
- Domaines publics : `*.caremelle.org` (via Cloudflare Tunnel)
- NetworkPolicies : default-deny ingress sur `valhafin`, `homepage`, `networking` (voir [architecture](docs/architecture.md#sécurité-réseau-networkpolicies))

## Observabilité

Le cluster intègre une stack d'observabilité complet, entièrement déployée via ArgoCD :

### Métriques & Alerting
- **Prometheus** (kube-prometheus-stack v72.9.1) : collecte des métriques cluster, node-exporter, kube-state-metrics
- **Alertmanager → Discord** : 8 règles d'alerting routées vers 2 canaux Discord (critiques 🚨 / warnings ⚠️)
- **blackbox-exporter** : probes HTTP sur les services exposés (valhafin, homepage)
- **postgres-exporter** : métriques PostgreSQL (connexions, taille base, requêtes)

### Logs centralisés
- **Loki** (mode Monolithic) : stockage des logs, rétention 7 jours, PVC 10 Gi
- **Alloy** (DaemonSet) : collecte filesystem `/var/log/pods/`, parsing CRI, labels namespace/pod/container

### Dashboards Grafana (config-as-code)
4 dashboards provisionnés automatiquement via sidecar ConfigMap :

| Dashboard | URL | Description |
|---|---|---|
| Cluster Overview | `/d/cluster-overview` | Santé nœuds, CPU/RAM, probes, PostgreSQL |
| Stockage | `/d/storage` | Utilisation disque VMs et PVCs |
| Réseau | `/d/network` | Trafic par nœud/pod, Traefik, latence |
| Logs | `/d/logs` | Logs filtrables par namespace/pod avec recherche |

Pour ajouter un dashboard : créer un fichier JSON dans `helm/prometheus-stack/dashboards/` et pousser sur Git.

Voir la [documentation détaillée du monitoring](docs/prometheus-stack/README.md).

## CI/CD

Deux workflows GitHub Actions dans `.github/workflows/` :

### Deploy k3s Cluster (`deploy.yml`)

Exécute le playbook Ansible complet sur le cluster.

| Déclencheur | Condition |
|---|---|
| Push sur `main` | Fichiers modifiés dans `ansible/` ou le workflow lui-même |
| Manuel (`workflow_dispatch`) | Choix de l'environnement (production / staging) |

Étapes :
1. Setup Python venv + installation des dépendances (`requirements-python.txt`)
2. Installation des collections Ansible (`requirements.txt`)
3. Configuration de la clé SSH (secret `K3S_SSH_PRIVATE_KEY`)
4. Test de connectivité SSH vers tous les nœuds (`ansible ping`)
5. Exécution du playbook (`ansible-playbook -i inventory.ini playbook.yml`)
6. Vérification du cluster (nœuds + pods système)
7. Cleanup de la clé SSH et du venv

Runner : **self-hosted** (accès réseau local requis pour SSH vers les nœuds).

### Security Audit (`security-audit.yml`)

Scanne le repository à la recherche de secrets en dur.

| Déclencheur | Condition |
|---|---|
| Push | Branches `main` et `develop` |
| Pull Request | Vers `main` et `develop` |
| Planifié | Chaque lundi à 2h du matin |
| Manuel (`workflow_dispatch`) | — |

Éléments scannés :
- Mots de passe hardcodés (`password: "..."`)
- Tokens (`token: "..."`)
- Clés API (`api_key: "..."`)
- Clés privées (`BEGIN PRIVATE KEY`)
- Credentials AWS
- Mots de passe SSH/sudo Ansible (`ansible_ssh_pass`, `ansible_become_pass`)
- Vérification de l'usage d'Ansible Vault
- Vérification que les credentials utilisent des variables (`{{ ... }}`)

Runner : **ubuntu-latest**. Le rapport d'audit est uploadé en artifact (rétention 90 jours). Le workflow échoue si des violations sont détectées.

## Documentation

Voir le dossier [`docs/`](docs/) pour la documentation détaillée :

- [Architecture](docs/architecture.md) — Vue d'ensemble de l'architecture du cluster
- [Guide Helmfile](docs/helmfile-upgrade.md) — Mise à jour de Helmfile
- [Sealed Secrets Valhafin](docs/valhafin-sealed-secrets.md) — Gestion des secrets Valhafin
- Documentation par application dans `docs/<app>/`

## Licence

Voir le fichier [LICENSE](LICENSE).
