# k3s Ansible Deployment

Déploiement automatisé d'un cluster k3s sur des VMs Ubuntu 24.04 hébergées sur Proxmox, avec orchestration Ansible et workflows GitHub Actions.

## 📋 Table des Matières

- [Vue d'Ensemble](#vue-densemble)
- [Prérequis](#prérequis)
- [Structure du Projet](#structure-du-projet)
- [Installation](#installation)
- [Utilisation](#utilisation)
- [Infrastructure avec Helmfile](#infrastructure-avec-helmfile)
- [Workflows GitHub Actions](#workflows-github-actions)
- [Sécurité](#sécurité)
- [Dépannage](#dépannage)

## 🎯 Vue d'Ensemble

Ce projet automatise le déploiement d'un cluster k3s avec:
- **1 nœud master** (k3s-master)
- **N nœuds workers** (k3s-worker-01+)
- **Outils GitOps** (kubectl, helm, helmfile) installés sur le master
- **Infrastructure automatisée** (ArgoCD) via Helmfile
- **Workflows CI/CD** pour déploiement et audit de sécurité

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Machine de Contrôle Ansible                │
│                  (ou GitHub Runner)                     │
└────────────────────┬────────────────────────────────────┘
                     │ SSH
        ┌────────────┼────────────┬───────────────┐
        │            │            │               │
   ┌────▼────┐  ┌───▼─────┐  ┌──▼──────┐   ┌───▼─────┐
   │ Master  │  │Worker-01│  │Worker-02│   │Worker-0N│
   │ :6443   │  │         │  │         │   │         │
   └────┬────┘  └────┬────┘  └────┬────┘   └────┬────┘
        │            │            │             │
        └────────────┴────────────┴─────────────┘
                  k3s Cluster Network
```

## 📁 Structure du Projet
```
.
├── ansible/
│   ├── inventory.ini              # Inventaire des hôtes
│   ├── playbook.yml               # Playbook principal
│   ├── ansible.cfg                # Configuration Ansible
│   ├── group_vars/
│   │   ├── all.yml                # Variables globales
│   │   └── k3s_cluster.yml        # Variables du cluster
│   └── roles/
│       ├── prepare_nodes/         # Préparation système
│       ├── k3s_master/            # Installation master
│       ├── k3s_workers/           # Installation workers
│       ├── gitops_tools/          # kubectl & helm
│       └── verify_cluster/        # Vérification
├── .github/
│   └── workflows/
│       ├── deploy.yml             # Workflow de déploiement
│       └── security-audit.yml     # Audit de sécurité
├── output/                        # Kubeconfig & token (local)
├── docs/                          # Documentation
└── README.md
```

## 🚀 Installation

### 1. Cloner le Repository

```bash
git clone <repository-url>
cd homelab-cluster
```

### 2. Configurer l'Inventaire

Éditer `ansible/inventory.ini` avec vos IPs:

```ini
[k3s_master]
k3s-master ansible_host=192.168.1.102

[k3s_workers]
k3s-worker-01 ansible_host=192.168.1.103
k3s-worker-02 ansible_host=192.168.1.104
# Ajouter d'autres workers si nécessaire

[k3s_cluster:children]
k3s_master
k3s_workers

[k3s_cluster:vars]
ansible_user=k3s
```

### 3. Vérifier la Connectivité

```bash
cd ansible
ansible all -i inventory.ini -m ping
```

Résultat attendu:
```
k3s-master | SUCCESS => {"ping": "pong"}
k3s-worker-01 | SUCCESS => {"ping": "pong"}
...
```

## 💻 Utilisation

### Déploiement Local

#### Déploiement Complet

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

#### Déploiement par Étapes

```bash
# 1. Préparer les nœuds uniquement
ansible-playbook -i inventory.ini playbook.yml --tags prepare

# 2. Installer le master uniquement
ansible-playbook -i inventory.ini playbook.yml --tags master

# 3. Installer les workers uniquement
ansible-playbook -i inventory.ini playbook.yml --tags workers

# 4. Installer les outils GitOps
ansible-playbook -i inventory.ini playbook.yml --tags gitops

# 5. Vérifier le cluster
ansible-playbook -i inventory.ini playbook.yml --tags verify
```

#### Mode Verbose

```bash
# Afficher les détails d'exécution
ansible-playbook -i inventory.ini playbook.yml -v

# Mode debug complet
ansible-playbook -i inventory.ini playbook.yml -vvv
```

### Récupération du Kubeconfig

Après le déploiement, récupèrer le kubeconfig depuis le master:

```bash
# Récupérer le kubeconfig
ssh k3s@192.168.1.102 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed 's/127.0.0.1/192.168.1.102/g' > ~/.kube/k3s-config

# Sécuriser les permissions
chmod 600 ~/.kube/k3s-config

# Utiliser le cluster
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

#### Option 2: Configuration Permanente

```bash
# Ajouter à votre ~/.bashrc
echo 'export KUBECONFIG=~/.kube/k3s-config' >> ~/.bashrc
source ~/.bashrc

# Maintenant kubectl utilise automatiquement ce kubeconfig
kubectl get nodes
```

### Récupération du Token (Optionnel)

Si on veut ajouter des workers manuellement:

```bash
# Ou manuellement
ssh k3s@192.168.1.102 "sudo cat /var/lib/rancher/k3s/server/node-token"
```

### Vérification du Cluster

```bash
# Vérifier les nœuds
kubectl get nodes -o wide

# Vérifier les pods système
kubectl get pods -A

# Vérifier la version
kubectl version

# Tester helm
helm version
```

## 🚢 Infrastructure avec Helmfile

Le système déploie automatiquement les composants d'infrastructure du cluster en utilisant Helmfile.

### Composants Disponibles

- **ArgoCD** (activé par défaut) : Déploiement continu GitOps
- **Sealed Secrets** (désactivé) : Gestion des secrets chiffrés
- **Cert-Manager** (désactivé) : Gestion des certificats TLS
- **Prometheus** (désactivé) : Surveillance et alertes

### Configuration

Les composants sont définis dans `helmfile.yaml` à la racine du projet. Pour activer/désactiver un composant, modifier le champ `installed`:

```yaml
releases:
  - name: argocd
    namespace: argocd
    chart: argo/argo-cd
    version: 5.51.6
    installed: true  # true = activé, false = désactivé
```

### Accès à ArgoCD

Après le déploiement, ArgoCD est accessible via NodePort :

```bash
# Obtenir le port NodePort
kubectl get service argocd-server -n argocd

# Obtenir le mot de passe admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Accéder à l'interface web
https://<master-ip>:<nodeport>
```

Identifiants par défaut :
- Utilisateur : `admin`
- Mot de passe : Voir commande ci-dessus

### Ajouter un Composant

1. Modifier `helmfile.yaml` à la racine du projet :
```yaml
releases:
  - name: sealed-secrets
    namespace: sealed-secrets
    chart: sealed-secrets/sealed-secrets
    version: 2.13.2
    installed: true  # Activer le composant
```

2. Exécuter le playbook :
```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml --tags gitops
```

3. Vérifier le déploiement :
```bash
kubectl get pods -n sealed-secrets
```

### Mise à Jour des Composants

Pour mettre à jour la version d'un composant :

1. Modifier la version dans `helmfile.yaml`
2. Exécuter : `ansible-playbook -i inventory.ini playbook.yml --tags gitops`
3. Helmfile détecte le changement et met à jour le composant

### Gestion Manuelle

Sur le nœud master, on peut gérer l'infrastructure manuellement :

```bash
# SSH vers le master
ssh k3s@192.168.1.102

# Afficher l'état des releases
helmfile status

# Afficher les différences
helmfile diff

# Synchroniser manuellement
helmfile sync

# Lister les releases
helmfile list

# Supprimer tous les composants
helmfile destroy
```

### Dépannage Helmfile

**Les pods ne démarrent pas** :
```bash
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl logs -n <namespace> <pod-name>
```

**Helmfile échoue** :
```bash
# Vérifier la syntaxe du manifest
helmfile lint

# Afficher les logs détaillés
helmfile sync --debug
```

**Réinitialiser l'infrastructure** :
```bash
# Supprimer les namespaces
kubectl delete namespace argocd sealed-secrets cert-manager monitoring

# Re-déployer
cd ansible
ansible-playbook -i inventory.ini playbook.yml --tags gitops
```

## 🤖 Workflows GitHub Actions

### Workflow de Déploiement

**Fichier**: `.github/workflows/deploy.yml`

**Déclenchement**:
- Manuel via l'interface GitHub (Actions → Deploy k3s Cluster → Run workflow)
- Automatique sur push vers `main` (si fichiers Ansible modifiés)

**Après le déploiement**:

Le workflow affiche les instructions pour récupérer le kubeconfig. Depuis la machine locale:

```bash
ssh k3s@192.168.1.102 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed 's/127.0.0.1/192.168.1.102/g' > ~/.kube/k3s-config
chmod 600 ~/.kube/k3s-config

# Utiliser le cluster
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

### Workflow d'Audit de Sécurité

**Fichier**: `.github/workflows/security-audit.yml`

**Déclenchement**:
- Automatique sur push/PR (si fichiers Ansible modifiés)
- Manuel via l'interface GitHub
- Planifié quotidiennement à 2h du matin

**Ce qui est vérifié**:
- ✅ Mots de passe en dur
- ✅ Tokens et clés API
- ✅ Clés SSH privées
- ✅ Credentials AWS
- ✅ Mots de passe SSH/sudo
- ✅ Utilisation d'Ansible Vault
- ✅ Utilisation de variables

## 🔍 Dépannage

### Problème: Installation k3s Échoue

```bash
# Vérifier les logs sur le nœud
ssh k3s@192.168.1.102
sudo journalctl -u k3s -f

# Vérifier l'état du service
sudo systemctl status k3s
```

### Problème: Workers Ne Rejoignent Pas le Cluster

```bash
# Vérifier la connectivité au master
ssh k3s@192.168.1.103
curl -k https://192.168.1.102:6443

# Vérifier le token
ssh k3s@192.168.1.102
sudo cat /var/lib/rancher/k3s/server/node-token

# Vérifier les logs du worker
ssh k3s@192.168.1.103
sudo journalctl -u k3s-agent -f
```

### Problème: Nœuds en État NotReady

```bash
# Vérifier les pods système
kubectl get pods -n kube-system

# Vérifier les événements
kubectl get events -A --sort-by='.lastTimestamp'

# Décrire un nœud
kubectl describe node k3s-worker-01
```

### Réinitialiser le Cluster

```bash
# Sur chaque nœud (master et workers)
ssh k3s@<node-ip>
sudo /usr/local/bin/k3s-uninstall.sh  # sur le master
sudo /usr/local/bin/k3s-agent-uninstall.sh  # sur les workers

# Relancer le déploiement
ansible-playbook -i inventory.ini playbook.yml
```

## 📝 Licence

Voir le fichier [LICENSE](LICENSE) pour plus de détails.
