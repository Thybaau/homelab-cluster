# Variables Centralisées - Documentation

Ce document liste toutes les variables centralisées dans `group_vars/` pour éviter les doublons.

## 📁 group_vars/all.yml

Variables globales utilisées par tous les hôtes:

### Versions
- `k3s_version: stable`
- `kubectl_version: stable`
- `helm_version: v3`

### Configuration Réseau
- `k3s_master_ip: 192.168.1.102`
- `k3s_api_port: 6443`

### Chemins
- `k3s_config_dir: /etc/rancher/k3s`
- `k3s_data_dir: /var/lib/rancher/k3s`
- `kubeconfig_local_path: ~/.kube/k3s-config` (machine de contrôle)

### Sécurité
- `k3s_token_file: /var/lib/rancher/k3s/server/node-token`
- `kubeconfig_permissions: "0600"`

### Timeouts (en secondes)
- `service_start_timeout: 60`
- `node_ready_timeout: 300`
- `verification_timeout: 300`
- `k3s_install_timeout: 300`
- `master_connectivity_timeout: 300`
- `retry_delay: 10`

### Dépendances Système
- `required_packages:` (liste des packages APT)
- `kernel_modules:` (br_netfilter, overlay)
- `sysctl_config:` (paramètres kernel)

### Firewall
- `firewall_ports:` (6443, 10250, 8472)

### Rapports
- `cluster_report_path: /tmp/cluster_status.txt`

## 📁 group_vars/k3s_cluster.yml

Variables spécifiques au cluster k3s:

### Installation k3s
- `k3s_install_script_url: https://get.k3s.io`

### Configuration Master
- `k3s_server_bind_address: "{{ k3s_master_ip }}"`
- `k3s_server_advertise_address: "{{ k3s_master_ip }}"`
- `k3s_server_node_ip: "{{ k3s_master_ip }}"`

### Configuration Workers
- `k3s_server_url: "https://{{ k3s_master_ip }}:{{ k3s_api_port }}"`

### kubectl
- `kubectl_download_url: "https://dl.k8s.io/release"`
- `kubectl_install_path: /usr/local/bin/kubectl`

### Helm
- `helm_install_script_url: https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3`
- `helm_install_path: /usr/local/bin/helm`

### Kubeconfig (sur les nœuds)
- `k3s_kubeconfig_file: "{{ k3s_config_dir }}/k3s.yaml"` (fichier original k3s)
- `kubeconfig_user_dir: /home/{{ ansible_user }}/.kube`
- `kubeconfig_user_file: "{{ kubeconfig_user_dir }}/config"` (copie pour l'utilisateur)

### Services
- `k3s_service_name: k3s`
- `k3s_agent_service_name: k3s-agent`

## 🎯 Variables Spécifiques aux Rôles

### verify_cluster/defaults/main.yml
- `expected_node_count: "{{ groups['k3s_cluster'] | length }}"` (calculé dynamiquement)

## ⚠️ Variables Supprimées (Doublons)

Les variables suivantes ont été supprimées des rôles car elles sont maintenant centralisées:

### prepare_nodes
- ❌ `required_packages` → utilise `group_vars/all.yml`
- ❌ `kernel_modules` → utilise `group_vars/all.yml`
- ❌ `sysctl_config` → utilise `group_vars/all.yml`
- ❌ `firewall_ports` → utilise `group_vars/all.yml`

### k3s_master
- ❌ `k3s_install_script_url` → utilise `group_vars/k3s_cluster.yml`
- ❌ `k3s_kubeconfig_file` → utilise `group_vars/k3s_cluster.yml`
- ❌ `k3s_token_file` → utilise `group_vars/all.yml`
- ❌ `k3s_service_name` → utilise `group_vars/k3s_cluster.yml`

### k3s_workers
- ❌ `k3s_version` → utilise `group_vars/all.yml`
- ❌ `k3s_master_url` → utilise `k3s_server_url` de `group_vars/k3s_cluster.yml`
- ❌ `k3s_master_ip` → utilise `group_vars/all.yml`
- ❌ `k3s_api_port` → utilise `group_vars/all.yml`
- ❌ `service_start_timeout` → utilise `group_vars/all.yml`

### gitops_tools
- ❌ `kubectl_version` → utilise `group_vars/all.yml`
- ❌ `helm_version` → utilise `group_vars/all.yml`
- ❌ `kubeconfig_path` → utilise `kubeconfig_user_file` de `group_vars/k3s_cluster.yml`
- ❌ `kubectl_bin_path` → utilise `kubectl_install_path` de `group_vars/k3s_cluster.yml`
- ❌ `helm_bin_path` → utilise `helm_install_path` de `group_vars/k3s_cluster.yml`

### verify_cluster
- ❌ `verification_timeout` → utilise `group_vars/all.yml`
- ❌ `retry_delay` → utilise `group_vars/all.yml`
- ❌ `cluster_report_path` → utilise `group_vars/all.yml`

## 📝 Bonnes Pratiques

1. **Toujours vérifier group_vars en premier** avant d'ajouter une variable dans un rôle
2. **Centraliser les valeurs communes** dans `all.yml`
3. **Utiliser k3s_cluster.yml** pour les variables spécifiques au cluster
4. **Garder les defaults/ des rôles vides** ou avec uniquement des variables calculées dynamiquement
5. **Documenter les changements** dans ce fichier

## 🔍 Comment Vérifier

Pour vérifier qu'aucune variable fantôme n'existe:

```bash
# Chercher les variables en dur dans les tasks
grep -r "k3s_master_ip:" ansible/roles/*/tasks/
grep -r "6443" ansible/roles/*/tasks/
grep -r "/etc/rancher/k3s" ansible/roles/*/tasks/

# Vérifier les doublons dans defaults
grep -r "k3s_version:" ansible/roles/*/defaults/
grep -r "kubectl_version:" ansible/roles/*/defaults/
```

Toutes ces commandes devraient retourner des résultats vides ou uniquement des références à des variables (avec `{{ }}`).
