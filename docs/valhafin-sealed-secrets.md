# Guide Sealed Secrets pour Valhafin

## Introduction

Ce guide explique comment générer et gérer les Sealed Secrets pour l'application Valhafin. Les Sealed Secrets permettent de stocker des données sensibles de manière sécurisée dans Git, ce qui est essentiel pour un workflow GitOps avec ArgoCD.

### Pourquoi Sealed Secrets ?

Dans un workflow GitOps, toute la configuration de l'infrastructure est stockée dans Git. Cependant, les Secrets Kubernetes standards contiennent des données encodées en base64, qui peuvent être facilement décodées. Cela pose un problème de sécurité majeur.

**Sealed Secrets résout ce problème en :**

- **Chiffrant les secrets** avec une clé publique avant de les stocker dans Git
- **Déchiffrant automatiquement** les secrets dans le cluster via le Sealed Secrets Controller
- **Permettant un workflow GitOps 100%** sans compromettre la sécurité
- **Garantissant que seul le cluster cible** peut déchiffrer les secrets

### Architecture

```
┌─────────────────┐
│  Développeur    │
└────────┬────────┘
         │ 1. Crée Secret en clair
         ▼
┌─────────────────┐
│  kubeseal CLI   │
└────────┬────────┘
         │ 2. Chiffre avec clé publique
         ▼
┌─────────────────┐
│  SealedSecret   │
│  (Git safe)     │
└────────┬────────┘
         │ 3. Commit dans Git
         ▼
┌─────────────────┐
│   ArgoCD        │
└────────┬────────┘
         │ 4. Déploie SealedSecret
         ▼
┌─────────────────┐
│  Kubernetes     │
└────────┬────────┘
         │ 5. Détecte nouveau SealedSecret
         ▼
┌─────────────────┐
│ Sealed Secrets  │
│   Controller    │
└────────┬────────┘
         │ 6. Déchiffre avec clé privée
         ▼
┌─────────────────┐
│  Secret K8s     │
│  (utilisable)   │
└─────────────────┘
```

## Prerequisites

Avant de commencer, assurez-vous d'avoir :

### 1. Sealed Secrets Controller installé dans le cluster

```bash
# Vérifier si le controller est installé
kubectl get pods -n kube-system | grep sealed-secrets

# Si non installé, installer le controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Vérifier que le controller est en cours d'exécution
kubectl get pods -n kube-system -l name=sealed-secrets-controller
```

### 2. kubeseal CLI installé localement

**Sur macOS :**
```bash
brew install kubeseal
```

**Sur Linux :**
```bash
# Télécharger la dernière version
KUBESEAL_VERSION='0.24.0'
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"

# Extraire et installer
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Vérifier l'installation
kubeseal --version
```

**Sur Windows :**
```powershell
# Avec Chocolatey
choco install kubeseal

# Ou télécharger depuis GitHub releases
# https://github.com/bitnami-labs/sealed-secrets/releases
```

### 3. Accès au cluster Kubernetes

```bash
# Vérifier l'accès au cluster
kubectl cluster-info

# Vérifier le contexte actuel
kubectl config current-context

# Si nécessaire, changer de contexte
kubectl config use-context <your-context>
```

### 4. Récupérer la clé publique du cluster

```bash
# Récupérer la clé publique du Sealed Secrets Controller
kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=kube-system > pub-cert.pem

# Vérifier le contenu de la clé
cat pub-cert.pem
```

**Important** : Cette clé publique est spécifique à votre cluster. Si vous changez de cluster ou réinstallez le Sealed Secrets Controller, vous devrez régénérer tous vos SealedSecrets.

## Step-by-Step Guide

### Étape 1 : Créer un Secret local en clair

Créez un fichier YAML contenant votre Secret Kubernetes standard avec les valeurs en clair.

#### Secret pour les credentials de la base de données

Créez un fichier `db-credentials-secret.yaml` :

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: valhafin-db-credentials
  namespace: valhafin
type: Opaque
stringData:
  POSTGRES_DB: valhafin
  POSTGRES_USER: valhafin_user
  POSTGRES_PASSWORD: your-secure-password-here
```

**Notes importantes :**
- Utilisez `stringData` pour les valeurs en clair (plus lisible que `data` en base64)
- Le `name` doit correspondre à celui référencé dans le Helm chart
- Le `namespace` doit être `valhafin`
- Remplacez `your-secure-password-here` par un mot de passe fort

**Générer un mot de passe sécurisé :**
```bash
# Générer un mot de passe aléatoire de 32 caractères
openssl rand -base64 32

# Ou avec pwgen
pwgen -s 32 1
```

#### Secret pour la clé de chiffrement du backend

Créez un fichier `backend-secrets-secret.yaml` :

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: valhafin-backend-secrets
  namespace: valhafin
type: Opaque
stringData:
  ENCRYPTION_KEY: your-encryption-key-here
```

**Générer une clé de chiffrement :**
```bash
# Générer une clé de chiffrement de 32 bytes (256 bits)
openssl rand -hex 32
```

### Étape 2 : Chiffrer avec kubeseal

Utilisez `kubeseal` pour chiffrer vos Secrets en SealedSecrets.

#### Chiffrer le secret de la base de données

```bash
# Méthode 1 : Chiffrer et sauvegarder dans un fichier
kubeseal --format=yaml --cert=pub-cert.pem < db-credentials-secret.yaml > db-credentials-sealedsecret.yaml

# Méthode 2 : Chiffrer directement depuis le cluster (sans fichier cert local)
kubeseal --format=yaml \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  < db-credentials-secret.yaml > db-credentials-sealedsecret.yaml
```

Le fichier `db-credentials-sealedsecret.yaml` généré ressemblera à :

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: valhafin-db-credentials
  namespace: valhafin
spec:
  encryptedData:
    POSTGRES_DB: AgBxK8F7Hn3...très-longue-chaîne-chiffrée...
    POSTGRES_PASSWORD: AgCY9mP2Qw1...très-longue-chaîne-chiffrée...
    POSTGRES_USER: AgDZ3nR4Tx5...très-longue-chaîne-chiffrée...
  template:
    metadata:
      name: valhafin-db-credentials
      namespace: valhafin
    type: Opaque
```

#### Chiffrer le secret du backend

```bash
kubeseal --format=yaml --cert=pub-cert.pem < backend-secrets-secret.yaml > backend-secrets-sealedsecret.yaml
```

Le fichier `backend-secrets-sealedsecret.yaml` généré ressemblera à :

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: valhafin-backend-secrets
  namespace: valhafin
spec:
  encryptedData:
    ENCRYPTION_KEY: AgAT7kL9Vy2...très-longue-chaîne-chiffrée...
  template:
    metadata:
      name: valhafin-backend-secrets
      namespace: valhafin
    type: Opaque
```

**Options importantes de kubeseal :**

- `--format=yaml` : Génère un fichier YAML (recommandé pour Git)
- `--format=json` : Génère un fichier JSON
- `--cert=pub-cert.pem` : Utilise une clé publique locale
- `--scope=strict` : Le secret ne peut être déchiffré que dans le namespace spécifié (défaut)
- `--scope=namespace-wide` : Le secret peut être déchiffré dans n'importe quel namespace
- `--scope=cluster-wide` : Le secret peut être déchiffré n'importe où dans le cluster

**Recommandation** : Utilisez toujours `--scope=strict` (défaut) pour une sécurité maximale.

### Étape 3 : Copier les valeurs encryptedData dans values.yaml

Maintenant que vous avez vos SealedSecrets chiffrés, vous devez copier les valeurs `encryptedData` dans le fichier `values.yaml` du Helm chart.

#### Ouvrir le fichier values.yaml

```bash
# Éditer le fichier values.yaml
vim homelab-cluster/helm/valhafin/values.yaml
# ou
code homelab-cluster/helm/valhafin/values.yaml
```

#### Remplacer les valeurs placeholder

Localisez la section `sealedSecrets` dans `values.yaml` :

```yaml
# Configuration des Sealed Secrets
sealedSecrets:
  enabled: true
  
  database:
    name: valhafin-db-credentials
    # Les valeurs encryptedData doivent être générées avec kubeseal
    encryptedData:
      POSTGRES_DB: "AgBxxx..."  # Placeholder - remplacer par valeur chiffrée
      POSTGRES_USER: "AgBxxx..."  # Placeholder - remplacer par valeur chiffrée
      POSTGRES_PASSWORD: "AgBxxx..."  # Placeholder - remplacer par valeur chiffrée
  
  backend:
    name: valhafin-backend-secrets
    encryptedData:
      ENCRYPTION_KEY: "AgBxxx..."  # Placeholder - remplacer par valeur chiffrée
```

Remplacez les valeurs placeholder par les valeurs chiffrées de vos SealedSecrets :

```yaml
# Configuration des Sealed Secrets
sealedSecrets:
  enabled: true
  
  database:
    name: valhafin-db-credentials
    encryptedData:
      POSTGRES_DB: "AgBxK8F7Hn3...votre-valeur-chiffrée-complète..."
      POSTGRES_USER: "AgDZ3nR4Tx5...votre-valeur-chiffrée-complète..."
      POSTGRES_PASSWORD: "AgCY9mP2Qw1...votre-valeur-chiffrée-complète..."
  
  backend:
    name: valhafin-backend-secrets
    encryptedData:
      ENCRYPTION_KEY: "AgAT7kL9Vy2...votre-valeur-chiffrée-complète..."
```

**Important** : Copiez les valeurs complètes, elles sont très longues (plusieurs centaines de caractères).

#### Vérifier le format

Assurez-vous que :
- Les valeurs sont entre guillemets doubles
- Il n'y a pas de retours à la ligne dans les valeurs chiffrées
- L'indentation YAML est correcte (2 espaces par niveau)

#### Commiter dans Git

```bash
# Ajouter le fichier modifié
git add homelab-cluster/helm/valhafin/values.yaml

# Commiter avec un message descriptif
git commit -m "feat: update sealed secrets for valhafin"

# Pousser vers le repository
git push origin main
```

**Sécurité** : Les valeurs chiffrées peuvent être stockées en toute sécurité dans Git. Seul le cluster possédant la clé privée correspondante peut les déchiffrer.

**Ne commitez JAMAIS les fichiers secrets en clair** (`db-credentials-secret.yaml`, `backend-secrets-secret.yaml`) dans Git !

```bash
# Supprimer les fichiers secrets en clair
rm db-credentials-secret.yaml backend-secrets-secret.yaml

# Ou les ajouter au .gitignore
echo "*-secret.yaml" >> .gitignore
```

## Examples

### Exemple Complet : Database Credentials

#### 1. Créer le Secret en clair

```bash
cat <<EOF > db-credentials-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: valhafin-db-credentials
  namespace: valhafin
type: Opaque
stringData:
  POSTGRES_DB: valhafin
  POSTGRES_USER: valhafin_user
  POSTGRES_PASSWORD: $(openssl rand -base64 32)
EOF
```

#### 2. Chiffrer avec kubeseal

```bash
kubeseal --format=yaml --cert=pub-cert.pem < db-credentials-secret.yaml > db-credentials-sealedsecret.yaml
```

#### 3. Extraire les valeurs chiffrées

```bash
# Afficher les valeurs chiffrées
cat db-credentials-sealedsecret.yaml | grep -A 3 "encryptedData:"
```

#### 4. Copier dans values.yaml

Copiez les valeurs affichées dans la section `sealedSecrets.database.encryptedData` de `values.yaml`.

#### 5. Nettoyer

```bash
# Supprimer le fichier secret en clair
rm db-credentials-secret.yaml

# Optionnel : Garder le SealedSecret pour référence
# (il peut être stocké dans Git en toute sécurité)
```

### Exemple Complet : Backend Encryption Key

#### 1. Créer le Secret en clair

```bash
cat <<EOF > backend-secrets-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: valhafin-backend-secrets
  namespace: valhafin
type: Opaque
stringData:
  ENCRYPTION_KEY: $(openssl rand -hex 32)
EOF
```

#### 2. Chiffrer avec kubeseal

```bash
kubeseal --format=yaml --cert=pub-cert.pem < backend-secrets-secret.yaml > backend-secrets-sealedsecret.yaml
```

#### 3. Extraire et copier la valeur chiffrée

```bash
# Afficher la valeur chiffrée
cat backend-secrets-sealedsecret.yaml | grep "ENCRYPTION_KEY:"
```

#### 4. Copier dans values.yaml

Copiez la valeur dans `sealedSecrets.backend.encryptedData.ENCRYPTION_KEY`.

#### 5. Nettoyer

```bash
rm backend-secrets-secret.yaml
```

### Exemple : Chiffrer une seule valeur

Si vous voulez chiffrer une seule valeur sans créer un fichier Secret complet :

```bash
# Chiffrer une valeur directement
echo -n "my-secret-value" | kubeseal --raw \
  --name=valhafin-db-credentials \
  --namespace=valhafin \
  --cert=pub-cert.pem

# La sortie est la valeur chiffrée que vous pouvez copier dans values.yaml
```

### Exemple : Mettre à jour un Secret existant

Si vous devez changer un mot de passe ou une clé :

```bash
# 1. Créer un nouveau Secret avec la nouvelle valeur
cat <<EOF > db-credentials-secret-new.yaml
apiVersion: v1
kind: Secret
metadata:
  name: valhafin-db-credentials
  namespace: valhafin
type: Opaque
stringData:
  POSTGRES_DB: valhafin
  POSTGRES_USER: valhafin_user
  POSTGRES_PASSWORD: new-secure-password
EOF

# 2. Chiffrer
kubeseal --format=yaml --cert=pub-cert.pem < db-credentials-secret-new.yaml > db-credentials-sealedsecret-new.yaml

# 3. Copier les nouvelles valeurs dans values.yaml

# 4. Commiter et pousser
git add homelab-cluster/helm/valhafin/values.yaml
git commit -m "chore: rotate database password"
git push

# 5. ArgoCD va automatiquement synchroniser et mettre à jour le Secret

# 6. Redémarrer les pods pour utiliser le nouveau Secret
kubectl rollout restart deployment -n valhafin valhafin-backend
kubectl rollout restart statefulset -n valhafin valhafin-database

# 7. Nettoyer
rm db-credentials-secret-new.yaml db-credentials-sealedsecret-new.yaml
```

## Troubleshooting

### Problème : kubeseal ne trouve pas le controller

**Symptômes** :
```
error: cannot fetch certificate: no endpoints available for service "sealed-secrets-controller"
```

**Solutions** :

```bash
# Vérifier que le controller est installé
kubectl get pods -n kube-system | grep sealed-secrets

# Si non installé, installer le controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Attendre que le pod soit prêt
kubectl wait --for=condition=ready pod -n kube-system -l name=sealed-secrets-controller --timeout=300s

# Réessayer de récupérer la clé publique
kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=kube-system > pub-cert.pem
```

### Problème : Les SealedSecrets ne sont pas déchiffrés

**Symptômes** :
- Les SealedSecrets existent dans le cluster
- Mais les Secrets correspondants ne sont pas créés
- Les pods ne démarrent pas avec des erreurs de secrets manquants

**Solutions** :

```bash
# Vérifier les SealedSecrets
kubectl get sealedsecrets -n valhafin

# Vérifier les Secrets générés
kubectl get secrets -n valhafin

# Vérifier les logs du controller
kubectl logs -n kube-system -l name=sealed-secrets-controller

# Causes courantes :
# 1. Namespace incorrect : Le SealedSecret doit être dans le même namespace que le Secret cible
# 2. Nom incorrect : Le nom doit correspondre exactement
# 3. Clé publique incorrecte : Le SealedSecret a été chiffré avec une clé différente

# Vérifier les événements
kubectl get events -n valhafin --sort-by='.lastTimestamp' | grep SealedSecret
```

### Problème : Erreur "cannot decrypt data"

**Symptômes** :
```
cannot decrypt data: no key could decrypt secret
```

**Cause** : Le SealedSecret a été chiffré avec une clé publique différente de celle du cluster actuel.

**Solutions** :

```bash
# 1. Vérifier que vous utilisez la bonne clé publique
kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=kube-system > pub-cert-current.pem

# 2. Comparer avec votre clé publique locale
diff pub-cert.pem pub-cert-current.pem

# 3. Si différentes, régénérer tous les SealedSecrets avec la nouvelle clé
kubeseal --format=yaml --cert=pub-cert-current.pem < db-credentials-secret.yaml > db-credentials-sealedsecret.yaml
kubeseal --format=yaml --cert=pub-cert-current.pem < backend-secrets-secret.yaml > backend-secrets-sealedsecret.yaml

# 4. Mettre à jour values.yaml avec les nouvelles valeurs chiffrées
```

### Problème : Valeurs chiffrées trop longues pour values.yaml

**Symptômes** : Les valeurs chiffrées sont très longues et rendent values.yaml difficile à lire.

**Solution Alternative** : Utiliser des fichiers SealedSecret séparés au lieu de les inclure dans values.yaml.

```bash
# 1. Créer les SealedSecrets comme des ressources séparées
# Les fichiers db-credentials-sealedsecret.yaml et backend-secrets-sealedsecret.yaml

# 2. Les placer dans le répertoire templates/
cp db-credentials-sealedsecret.yaml homelab-cluster/helm/valhafin/templates/
cp backend-secrets-sealedsecret.yaml homelab-cluster/helm/valhafin/templates/

# 3. Désactiver la génération depuis values.yaml
# Dans values.yaml :
sealedSecrets:
  enabled: false  # Les SealedSecrets sont maintenant des fichiers statiques

# 4. Commiter les fichiers
git add homelab-cluster/helm/valhafin/templates/*-sealedsecret.yaml
git commit -m "feat: add sealed secrets as separate resources"
```

**Note** : Cette approche est valide mais moins flexible car les valeurs ne peuvent pas être surchargées via values.yaml.

### Problème : Rotation des clés du Sealed Secrets Controller

**Symptômes** : Le Sealed Secrets Controller a été réinstallé ou les clés ont été régénérées.

**Impact** : Tous les SealedSecrets existants ne peuvent plus être déchiffrés.

**Solution** : Régénérer tous les SealedSecrets avec la nouvelle clé publique.

```bash
# 1. Récupérer la nouvelle clé publique
kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=kube-system > pub-cert-new.pem

# 2. Recréer les Secrets en clair (depuis une sauvegarde sécurisée ou un gestionnaire de mots de passe)
# IMPORTANT : Vous devez avoir conservé les valeurs en clair quelque part de sécurisé !

# 3. Rechiffrer tous les secrets
kubeseal --format=yaml --cert=pub-cert-new.pem < db-credentials-secret.yaml > db-credentials-sealedsecret.yaml
kubeseal --format=yaml --cert=pub-cert-new.pem < backend-secrets-secret.yaml > backend-secrets-sealedsecret.yaml

# 4. Mettre à jour values.yaml avec les nouvelles valeurs

# 5. Commiter et déployer
git add homelab-cluster/helm/valhafin/values.yaml
git commit -m "chore: regenerate sealed secrets after key rotation"
git push
```

**Recommandation** : Conservez toujours une copie sécurisée des valeurs en clair dans un gestionnaire de mots de passe (1Password, Bitwarden, Vault, etc.) pour pouvoir régénérer les SealedSecrets si nécessaire.

### Problème : Déchiffrement manuel d'un SealedSecret

**Cas d'usage** : Vous voulez vérifier la valeur déchiffrée d'un SealedSecret sans le déployer.

**Solution** :

```bash
# Récupérer le Secret déchiffré depuis le cluster
kubectl get secret -n valhafin valhafin-db-credentials -o yaml

# Décoder une valeur spécifique
kubectl get secret -n valhafin valhafin-db-credentials -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d

# Afficher toutes les valeurs décodées
kubectl get secret -n valhafin valhafin-db-credentials -o json | jq -r '.data | map_values(@base64d)'
```

**Note** : Cette commande nécessite que le SealedSecret ait déjà été déployé et déchiffré par le controller.

## Bonnes Pratiques

### Sécurité

1. **Ne jamais commiter les Secrets en clair dans Git**
   ```bash
   # Ajouter au .gitignore
   echo "*-secret.yaml" >> .gitignore
   echo "!*-sealedsecret.yaml" >> .gitignore
   ```

2. **Conserver une copie sécurisée des valeurs en clair**
   - Utiliser un gestionnaire de mots de passe (1Password, Bitwarden, Vault)
   - Documenter où les valeurs sont stockées
   - Mettre en place un processus de rotation régulière

3. **Utiliser des mots de passe forts**
   ```bash
   # Générer des mots de passe sécurisés
   openssl rand -base64 32
   pwgen -s 32 1
   ```

4. **Limiter l'accès à la clé privée du cluster**
   - Seul le Sealed Secrets Controller doit avoir accès à la clé privée
   - Restreindre l'accès RBAC au namespace kube-system
   - Auditer les accès régulièrement

5. **Utiliser le scope strict**
   ```bash
   # Toujours utiliser --scope=strict (défaut)
   kubeseal --format=yaml --scope=strict --cert=pub-cert.pem < secret.yaml > sealedsecret.yaml
   ```

### Workflow

1. **Automatiser la génération des SealedSecrets**
   ```bash
   # Créer un script pour générer tous les secrets
   #!/bin/bash
   set -e
   
   # Récupérer la clé publique
   kubeseal --fetch-cert > pub-cert.pem
   
   # Chiffrer tous les secrets
   for secret in secrets/*-secret.yaml; do
     output="${secret/-secret.yaml/-sealedsecret.yaml}"
     kubeseal --format=yaml --cert=pub-cert.pem < "$secret" > "$output"
     echo "Generated $output"
   done
   
   echo "All secrets encrypted successfully"
   ```

2. **Valider les SealedSecrets avant de commiter**
   ```bash
   # Vérifier que les SealedSecrets sont valides
   kubectl apply --dry-run=client -f db-credentials-sealedsecret.yaml
   kubectl apply --dry-run=client -f backend-secrets-sealedsecret.yaml
   ```

3. **Documenter le processus**
   - Maintenir ce guide à jour
   - Documenter où les valeurs en clair sont stockées
   - Documenter le processus de rotation des secrets

4. **Tester dans un environnement de staging**
   - Toujours tester les nouveaux SealedSecrets dans un environnement de test
   - Vérifier que les pods démarrent correctement
   - Vérifier que l'application fonctionne avec les nouveaux secrets

### Maintenance

1. **Rotation régulière des secrets**
   - Planifier une rotation tous les 90 jours minimum
   - Automatiser le processus de rotation si possible
   - Documenter les dates de rotation

2. **Sauvegarde de la clé privée du controller**
   ```bash
   # Sauvegarder la clé privée du Sealed Secrets Controller
   kubectl get secret -n kube-system sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
   
   # Stocker cette sauvegarde dans un endroit sécurisé (PAS dans Git !)
   # Par exemple : Vault, gestionnaire de mots de passe, coffre-fort physique
   ```

3. **Monitoring**
   - Surveiller les logs du Sealed Secrets Controller
   - Configurer des alertes en cas d'échec de déchiffrement
   - Auditer les accès aux secrets régulièrement

4. **Documentation**
   - Maintenir un inventaire des secrets
   - Documenter qui a accès à quoi
   - Documenter le processus de récupération en cas de perte de clés

## Ressources Complémentaires

### Documentation Officielle

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

### Outils Complémentaires

- [kubeseal](https://github.com/bitnami-labs/sealed-secrets/releases) - CLI pour chiffrer les secrets
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - CLI Kubernetes
- [ArgoCD](https://argo-cd.readthedocs.io/) - Déploiement GitOps

### Alternatives

Si Sealed Secrets ne convient pas à votre cas d'usage, considérez ces alternatives :

- **External Secrets Operator** : Synchronise les secrets depuis des gestionnaires externes (Vault, AWS Secrets Manager, etc.)
- **SOPS** : Chiffre les fichiers YAML/JSON avec des clés KMS
- **Vault** : Gestionnaire de secrets centralisé avec API
- **Git-crypt** : Chiffre automatiquement les fichiers dans Git

## Support

Pour toute question ou problème :

1. Consultez la section Troubleshooting ci-dessus
2. Vérifiez les logs du Sealed Secrets Controller
3. Consultez la documentation officielle
4. Ouvrez une issue sur le repository GitHub du projet

## Changelog

- **2024-01** : Création du guide initial
- Ajoutez vos modifications ici lors des mises à jour

---

**Note de sécurité** : Ce guide contient des informations sensibles sur la gestion des secrets. Assurez-vous de suivre les bonnes pratiques de sécurité et de ne jamais exposer les valeurs en clair dans des environnements non sécurisés.
