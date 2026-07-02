# Système de mise à jour automatique

Ce document décrit le système complet de mise à jour automatique du cluster homelab. Quatre composants travaillent ensemble pour maintenir le cluster à jour avec un minimum d'intervention manuelle : **Renovate** (dépendances déclaratives), **System Upgrade Controller** (K3s), **Kured** (redémarrage nœuds), et le **workflow CI/CD Ansible** (déploiement infra).

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         Flux de mise à jour automatique                         │
└─────────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────┐       PR auto         ┌──────────────┐      push main
  │   Renovate   │ ─────────────────────►│    GitHub    │ ──────────────────┐
  │  (Bot SaaS)  │   (images, charts,    │  (repo Git)  │                   │
  │              │   CLI tools, deps)    │              │                   │
  └──────────────┘                       └──────────────┘                   │
                                                                            ▼
                                                                   ┌──────────────────┐
                                                                   │  GitHub Actions  │
                                                                   │  (CI/CD Ansible) │
                                                                   └────────┬─────────┘
                                                                            │ ansible-playbook
                                                                            ▼
  ┌──────────────┐   sync auto    ┌──────────────┐            ┌──────────────────┐
  │    ArgoCD    │ ◄───────────── │  Git (main)  │            │   Nœuds k3s      │
  │  (GitOps)    │                │              │            │ (master+workers) │
  └──────┬───────┘                └──────────────┘            └──────────────────┘
         │                                                              ▲
         │ déploie                                                      │ SSH
         ▼                                                              │
  ┌──────────────┐                                           ┌──────────────────┐
  │  SUC + Kured │                                           │  GitHub Runner   │
  │ (in-cluster) │                                           │  (self-hosted)   │
  └──────────────┘                                           └──────────────────┘

  SUC : vérifie le channel K3s stable → upgrade rolling des nœuds
  Kured : détecte /var/run/reboot-required → reboot planifié dimanche 03h-05h
```

## Composants

### 1. Renovate — Gestion des dépendances déclaratives

[Renovate](https://docs.renovatebot.com/) est un bot SaaS qui scanne le repository, détecte les dépendances obsolètes, et ouvre des Pull Requests automatiques pour les mettre à jour.

**Configuration** : [`renovate.json5`](../renovate.json5)

#### Ce que Renovate met à jour

| Catégorie | Fichiers ciblés | Manager | Exemples |
|---|---|---|---|
| Images Docker | `helm/*/values.yaml` | `helm-values` | PostgreSQL, Redis, app images |
| Charts Helm upstream | `argocd-apps/*.yml` | `argocd` | kured, prometheus-stack, loki |
| Infrastructure Helmfile | `helmfile.yaml` | `helmfile` | ArgoCD |
| CLI tools | `ansible/group_vars/all.yml` | `custom.regex` | kubectl, helm, helmfile |
| GitHub Actions | `.github/workflows/*.yml` | `github-actions` | actions/checkout, etc. |
| Python deps | `requirements-python.txt` | `pip_requirements` | ansible, kubernetes SDK |

#### Custom manager pour les CLI tools

Les versions des outils CLI (kubectl, helm, helmfile) sont déclarées dans `ansible/group_vars/all.yml` avec des annotations Renovate :

```yaml
# renovate: datasource=github-releases depName=kubernetes/kubernetes
kubectl_version: v1.36.2
# renovate: datasource=github-releases depName=helm/helm
helm_version: v3.21.2
# renovate: datasource=github-releases depName=helmfile/helmfile
helmfile_version: v1.6.0
```

Le custom manager extrait ces versions via regex et les compare aux releases GitHub.

#### Politiques d'automerge

| Type de mise à jour | Politique | Délai minimum | Planning |
|---|---|---|---|
| **Patch** (images, charts, CLI, Actions) | ✅ Automerge | 3 jours | Heures creuses* |
| **Minor** (images, charts, CLI, Actions) | ✅ Automerge | 7 jours | Week-end uniquement |
| **Major** (tout) | ❌ Review manuelle | — | — |
| **Infrastructure critique** (Helmfile) | ❌ Review manuelle | — | — |
| **Composants sensibles** (sealed-secrets, metallb, traefik-tls) | ❌ Review manuelle | 14 jours | — |
| **PostgreSQL major** | 🚫 Désactivé | — | — |
| **Valhafin (images privées)** | ❌ Review manuelle | — | — |

*Heures creuses = après 20h en semaine, avant 8h en semaine, tout le week-end.

#### Groupement des PRs

Pour éviter une avalanche de PRs individuelles, Renovate regroupe certaines mises à jour :

- **`monitoring-stack`** : prometheus-stack, loki, alloy, blackbox-exporter, postgres-exporter (values)
- **`monitoring-stack-charts`** : les mêmes composants côté charts upstream (ArgoCD apps)
- **`cli-tools`** : kubectl, helm, helmfile

#### Limites de débit

- Maximum 5 PRs par heure
- Maximum 10 PRs simultanées ouvertes
- Dependency Dashboard activé pour le suivi global

---

### 2. System Upgrade Controller (SUC) — Mise à jour K3s

Le [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) est un contrôleur Kubernetes qui gère les mises à jour rolling de K3s en suivant un channel de release.

**Déploiement** : chart local dans [`helm/system-upgrade-controller/`](../helm/system-upgrade-controller/)
**ArgoCD App** : [`argocd-apps/system-upgrade-controller-app.yml`](../argocd-apps/system-upgrade-controller-app.yml)
**Namespace** : `system-upgrade`

#### Fonctionnement

```
┌───────────────────────────────────────────────────────────────────┐
│                System Upgrade Controller (SUC)                     │
└───────────────────────────────────────────────────────────────────┘

  1. SUC interroge le channel K3s stable :
     https://update.k3s.io/v1-release/channels/stable

  2. Si une nouvelle version stable est disponible :

     ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
     │ server-plan │ ──OK──► │ agent-plan  │ ──OK──► │   Terminé   │
     │ (master)    │         │ (workers)   │         │             │
     └─────────────┘         └─────────────┘         └─────────────┘

  3. Chaque plan :
     - Cordon le nœud (pas de nouveaux pods)
     - Exécute l'upgrade K3s via rancher/k3s-upgrade
     - Nettoie les anciens répertoires de données K3s
     - Uncordon le nœud
```

#### Plans d'upgrade

Deux `Plan` CRDs définissent la stratégie :

**server-plan** (master nodes) :
- Sélecteur : `node-role.kubernetes.io/control-plane: "true"`
- Concurrence : 1 nœud à la fois
- Cordon avant upgrade
- Nettoyage automatique des anciens répertoires K3s orphelins

**agent-plan** (worker nodes) :
- Sélecteur : nodes sans le label control-plane
- Étape `prepare` : attend que le server-plan soit terminé avant de commencer
- Concurrence : 1 nœud à la fois
- Même nettoyage post-upgrade

#### Configuration clé

```yaml
plans:
  channel: https://update.k3s.io/v1-release/channels/stable
  upgradeImage: rancher/k3s-upgrade
  server:
    concurrency: 1
  agent:
    concurrency: 1
```

#### Cohérence avec Ansible

Le playbook Ansible utilise aussi `k3s_channel: stable` pour l'installation initiale, garantissant que :
- L'installation initiale (Ansible) et les upgrades (SUC) utilisent la même source de vérité
- Un redéploiement Ansible ne crée pas de conflit de version

#### Pas de fenêtre de maintenance

Le CRD `Plan` du SUC ne supporte pas de fenêtre de maintenance native. Les upgrades se déclenchent dès qu'une nouvelle version stable est publiée sur le channel. La cadence est contrôlée par le fait que seules les versions marquées "stable" par Rancher sont proposées.

---

### 3. Kured — Redémarrage automatique des nœuds

[Kured](https://kured.dev/) (KUbernetes REboot Daemon) est un DaemonSet qui détecte quand un nœud nécessite un redémarrage (après une mise à jour kernel par exemple) et orchestre le reboot de manière sûre.

**Déploiement** : chart upstream `kubereboot/kured` v6.0.0 via ArgoCD multi-source
**Values** : [`helm/kured/values.yaml`](../helm/kured/values.yaml)
**ArgoCD App** : [`argocd-apps/kured-app.yml`](../argocd-apps/kured-app.yml)
**Namespace** : `kube-system`

#### Fonctionnement

```
┌──────────────────────────────────────────────────────────────────────┐
│                          Flux Kured                                    │
└──────────────────────────────────────────────────────────────────────┘

  Nœud : apt upgrade installe un nouveau kernel
       │
       ▼
  /var/run/reboot-required apparaît (fichier sentinel)
       │
       ▼
  Kured détecte le sentinel (vérification toutes les 1h)
       │
       ▼
  Vérification des conditions :
    ✓ Dimanche entre 03:00 et 05:00 (Europe/Paris) ?
    ✓ Aucune alerte critique Prometheus active ?
       │
       ▼
  ⏳ Drain du nœud (timeout 5min, grace period 30s)
       │ notification Discord
       ▼
  🔄 Reboot du nœud
       │ notification Discord
       ▼
  ✅ Uncordon du nœud
       │ notification Discord
       ▼
  Nœud opérationnel
```

#### Fenêtre de maintenance

| Paramètre | Valeur |
|---|---|
| Jours autorisés | Dimanche uniquement |
| Plage horaire | 03:00 – 05:00 (Europe/Paris) |
| Concurrence | 1 nœud à la fois |
| Intervalle de vérification | 1 heure |

#### Intégration Prometheus

Kured interroge Prometheus avant chaque reboot pour s'assurer qu'aucune alerte critique n'est active. Si une alerte bloquante est en cours, le reboot est reporté.

**Alertes bloquantes** (regexp) :
- `StorageCritical`
- `NodeNotReady`
- `PodCrashLooping`
- `K3sUpgradeJobFailed`
- `AlertmanagerFailedNotifications`

Les alertes de niveau warning (StorageWarning, ServiceDown) ne bloquent **pas** les reboots.

#### Notifications Discord

Kured envoie des notifications Discord à chaque étape :
- ⏳ Drain en cours (reboot imminent)
- 🔄 Reboot du nœud
- ✅ Nœud rebooté et uncordoned

Le webhook Discord est stocké dans un `SealedSecret` (`kured-discord-webhook`).

#### Tolérations

Kured tourne aussi sur les nœuds control-plane grâce à la tolérance :
```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

---

### 4. Workflow CI/CD Ansible — Déploiement infrastructure

Le workflow GitHub Actions [`deploy.yml`](../.github/workflows/deploy.yml) applique les changements d'infrastructure au cluster via Ansible.

#### Déclencheurs

| Événement | Condition |
|---|---|
| Push sur `main` | Fichiers modifiés dans `ansible/`, `helmfile.yaml`, ou le workflow |
| Manuel (`workflow_dispatch`) | Choix de l'environnement |

#### Ce qu'il fait

Quand Renovate merge une PR qui modifie `ansible/group_vars/all.yml` (versions CLI) ou `helmfile.yaml` (version ArgoCD), le workflow se déclenche automatiquement :

1. Installe Python + dépendances Ansible dans un venv
2. Configure la clé SSH (secret GitHub)
3. Teste la connectivité vers les nœuds
4. Exécute le playbook Ansible complet
5. Vérifie l'état du cluster (nœuds + pods)
6. Nettoie les credentials

Le playbook Ansible met à jour les CLI tools (kubectl, helm, helmfile) sur le master node avec les nouvelles versions.

#### Runner self-hosted

Le runner GitHub Actions est hébergé localement (même réseau que le cluster) pour l'accès SSH direct aux nœuds.

---

## Flux complets de mise à jour

### Mise à jour d'une image Docker (ex: PostgreSQL 16.5.0 → 16.5.1)

```
1. Renovate détecte la nouvelle version (scan périodique)
2. Renovate ouvre une PR modifiant helm/valhafin/values.yaml
3. Attente 3 jours (minimumReleaseAge pour patch)
4. Automerge de la PR
5. ArgoCD détecte le changement sur main (sync automatique)
6. ArgoCD déploie la nouvelle version du pod
```

### Mise à jour de K3s (ex: v1.31.3 → v1.31.4)

```
1. Rancher publie une nouvelle version sur le channel "stable"
2. SUC détecte la mise à jour disponible
3. server-plan s'exécute : cordon master → upgrade → uncordon
4. agent-plan attend la fin du server-plan
5. agent-plan s'exécute : cordon worker → upgrade → uncordon (un par un)
6. Cluster entièrement mis à jour
```

### Mise à jour kernel OS → reboot nœud

```
1. unattended-upgrades (Ubuntu) installe un nouveau kernel
2. /var/run/reboot-required est créé
3. Kured détecte le fichier sentinel (vérification horaire)
4. Kured attend la fenêtre : dimanche 03:00-05:00
5. Kured vérifie Prometheus (pas d'alerte critique)
6. Drain → Reboot → Uncordon (notifications Discord à chaque étape)
```

### Mise à jour CLI tools (ex: kubectl v1.36.1 → v1.36.2)

```
1. Renovate détecte la nouvelle release GitHub
2. PR ouverte modifiant ansible/group_vars/all.yml
3. Attente 3 jours (patch) ou 7 jours + week-end (minor)
4. Automerge de la PR
5. GitHub Actions déclenche le workflow deploy.yml
6. Ansible met à jour kubectl/helm/helmfile sur le master
```

---

## Tableau récapitulatif

| Composant | Cible | Déclencheur | Automatisation | Fenêtre |
|---|---|---|---|---|
| Renovate | Images, charts, CLI, deps | Scan périodique | PR auto + automerge selon politique | Heures creuses |
| SUC | K3s (binaire) | Channel stable | Rolling upgrade automatique | Aucune (dès disponibilité) |
| Kured | Nœuds (reboot kernel) | Fichier sentinel | Reboot planifié | Dimanche 03:00-05:00 |
| CI/CD Ansible | Infra (CLI tools, ArgoCD) | Push sur main | Playbook automatique | Immédiat au merge |
| ArgoCD | Apps Kubernetes | Git sync | Déploiement continu | Immédiat |

---

## Garanties de sécurité

- **Pas de downtime K3s** : upgrades rolling (1 nœud à la fois), agents attendent que le master soit terminé
- **Pas de reboot intempestif** : fenêtre stricte dimanche nuit + vérification alertes Prometheus
- **Pas de version instable** : K3s utilise uniquement le channel "stable" (versions testées)
- **Pas d'automerge dangereux** : composants critiques (sealed-secrets, metallb, traefik-tls) et majors toujours en review manuelle
- **Délai de sécurité** : 3 à 14 jours selon la criticité avant automerge
- **Notifications** : Discord pour les reboots, Dependency Dashboard pour les PRs Renovate
