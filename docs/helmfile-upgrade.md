# Guide de mise à jour de Helmfile

Ce document explique comment mettre à jour la version de Helmfile utilisée dans le cluster k3s.

## Processus de mise à jour

Pour mettre à jour Helmfile vers une nouvelle version, vous devez modifier uniquement 2 variables dans le fichier `ansible/group_vars/all.yml`.

### Variables à modifier

1. **`helmfile_version`** : La nouvelle version souhaitée (format: `vX.Y.Z`)
2. **`helmfile_checksum`** : Le checksum SHA256 correspondant à la nouvelle version

> **Note** : L'URL de téléchargement (`helmfile_download_url`) se met à jour automatiquement grâce au templating Jinja2 qui utilise la variable `{{ helmfile_version }}`.

## Étapes détaillées

### 1. Récupérer le checksum de la nouvelle version

Utilisez la commande suivante en remplaçant `X.Y.Z` par la version souhaitée :

```bash
curl -sL https://github.com/helmfile/helmfile/releases/download/vX.Y.Z/helmfile_X.Y.Z_checksums.txt | grep "linux_amd64"
```

**Exemple pour la version 0.164.0** :
```bash
curl -sL https://github.com/helmfile/helmfile/releases/download/v0.164.0/helmfile_0.164.0_checksums.txt | grep "linux_amd64"
```

Cette commande affichera une ligne comme :
```
a1b2c3d4e5f6...  helmfile_0.164.0_linux_amd64.tar.gz
```

Copiez le checksum (la première partie avant les espaces).

### 2. Mettre à jour les variables

Éditez le fichier `ansible/group_vars/all.yml` et modifiez les deux variables :

```yaml
# Versions
helmfile_version: v0.164.0  # Nouvelle version

# Helmfile Configuration
helmfile_checksum: "sha256:a1b2c3d4e5f6..."  # Nouveau checksum
```

### 3. Déployer la mise à jour

Relancez le playbook Ansible avec le tag `gitops` pour installer la nouvelle version :

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml --tags gitops
```

### 4. Vérifier l'installation

Connectez-vous au nœud master et vérifiez la version installée :

```bash
ssh k3s@192.168.1.102 "helmfile version"
```

## Exemple complet

Mise à jour de la version 0.163.1 vers 0.164.0 :

```bash
# 1. Récupérer le checksum
curl -sL https://github.com/helmfile/helmfile/releases/download/v0.164.0/helmfile_0.164.0_checksums.txt | grep "linux_amd64"

# Résultat (exemple) :
# b8c9d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1  helmfile_0.164.0_linux_amd64.tar.gz

# 2. Éditer ansible/group_vars/all.yml
# Changer :
#   helmfile_version: v0.164.0
#   helmfile_checksum: "sha256:b8c9d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1"

# 3. Déployer
cd ansible
ansible-playbook -i inventory.ini playbook.yml --tags gitops

# 4. Vérifier
ssh k3s@192.168.1.102 "helmfile version"
```

## Notes importantes

- **Idempotence** : Le playbook Ansible vérifie la version installée avant de télécharger. Si la version est déjà installée, aucune action n'est effectuée.
- **Sécurité** : Le checksum garantit l'intégrité du binaire téléchargé. Ne sautez jamais cette étape.
- **Compatibilité** : Vérifiez les notes de version de Helmfile pour les changements incompatibles avant de mettre à jour.
- **Rollback** : Pour revenir à une version précédente, suivez le même processus avec l'ancienne version et son checksum.

## Ressources

- [Releases Helmfile sur GitHub](https://github.com/helmfile/helmfile/releases)
- [Documentation Helmfile](https://helmfile.readthedocs.io/)
