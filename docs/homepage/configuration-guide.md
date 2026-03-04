# Guide de Configuration - Homepage

Ce guide explique comment personnaliser votre déploiement homepage en modifiant le fichier `values.yaml` du Helm chart.

## Architecture de configuration

Homepage utilise trois sources de configuration :

1. **values.yaml** : Configuration du Helm chart (ressources, ingress, etc.)
2. **ConfigMap** : Configuration de l'interface homepage (généré depuis values.yaml)
3. **Variables d'environnement** : Credentials sensibles (optionnel)

## Configuration du widget Proxmox

Le widget Proxmox permet de monitorer votre hyperviseur directement depuis homepage.

### Prérequis

- Proxmox VE accessible depuis le cluster Kubernetes
- Compte utilisateur Proxmox avec permissions de lecture
- Token API Proxmox (recommandé) ou mot de passe

### Créer un token API Proxmox

1. Connectez-vous à l'interface Proxmox (https://192.168.1.200:8006)
2. Allez dans **Datacenter** → **Permissions** → **API Tokens**
3. Cliquez sur **Add** et créez un token :
   - **User** : `root@pam` (ou un utilisateur dédié)
   - **Token ID** : `homepage`
   - **Privilege Separation** : Décoché (pour hériter des permissions de l'utilisateur)
4. Notez le **Token Secret** (affiché une seule fois)

### Configuration avec SealedSecret (recommandé)

Pour sécuriser vos credentials Proxmox, utilisez un SealedSecret :

```bash
# Créer et sceller le secret
kubectl create secret generic homepage-proxmox \
  --from-literal=PROXMOX_USERNAME="root@pam!homepage" \
  --from-literal=PROXMOX_TOKEN="votre-token-secret" \
  --namespace=homepage \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets -o yaml > helm/homepage/templates/proxmox-sealedsecret.yaml
```

Éditez le fichier `helm/homepage/values.yaml` pour activer Proxmox :

```yaml
config:
  proxmox:
    enabled: true
    url: "https://192.168.1.200:8006"
    # Les credentials sont injectés automatiquement via le SealedSecret
```

### Appliquer la configuration

```bash
# Commit et push les changements
git add helm/homepage/templates/proxmox-sealedsecret.yaml
git add helm/homepage/values.yaml
git commit -m "Configure Proxmox widget with SealedSecret"
git push

# ArgoCD synchronisera automatiquement (selfHeal activé)
# Ou forcer la synchronisation :
argocd app sync homepage
```

### Vérifier le widget

1. Accédez à `http://homepage.local`
2. Le widget Proxmox devrait afficher :
   - Nombre de VMs actives
   - Nombre de containers actifs
   - Utilisation CPU du node
   - Utilisation RAM du node

### Dépannage du widget Proxmox

Si le widget affiche "Connection Error" :

```bash
# Vérifier les logs homepage
kubectl logs -n homepage -l app.kubernetes.io/name=homepage | grep -i proxmox

# Tester la connectivité depuis le pod
kubectl exec -it -n homepage deployment/homepage -- \
  curl -k https://192.168.1.200:8006/api2/json/version

# Vérifier les credentials dans le ConfigMap
kubectl get configmap homepage-config -n homepage -o yaml | grep -A 10 proxmox
```

## Personnalisation des services et widgets

### Ajouter des services personnalisés

Vous pouvez ajouter vos propres services à la page d'accueil :

```yaml
config:
  customServices:
    - name: "Monitoring"
      services:
        - name: "Prometheus"
          icon: "prometheus.png"
          href: "http://prometheus.local"
          description: "Métriques et alerting"
          widget:
            type: "prometheus"
            url: "http://prometheus.local"
        
        - name: "Grafana"
          icon: "grafana.png"
          href: "http://grafana.local"
          description: "Visualisation de métriques"
    
    - name: "Applications"
      services:
        - name: "Nextcloud"
          icon: "nextcloud.png"
          href: "https://nextcloud.local"
          description: "Stockage cloud personnel"
```

### Ajouter des widgets personnalisés

Homepage supporte de nombreux widgets pour monitorer vos services :

```yaml
config:
  customWidgets:
    # Widget météo
    - type: "openweathermap"
      apiKey: "votre-api-key"
      latitude: "48.8566"
      longitude: "2.3522"
      units: "metric"
    
    # Widget recherche
    - type: "search"
      provider: "google"
      target: "_blank"
```

### Widgets disponibles

Homepage supporte de nombreux types de widgets :

- **Infrastructure** : Proxmox, Docker, Kubernetes, Portainer
- **Monitoring** : Prometheus, Grafana, Uptime Kuma
- **Media** : Plex, Jellyfin, Sonarr, Radarr
- **Réseau** : Pi-hole, AdGuard Home, Unifi
- **Système** : Resources (CPU/RAM/Disk), Datetime, Search

Consultez la [documentation officielle](https://gethomepage.dev/en/widgets/) pour la liste complète.

## Options de values.yaml

### Configuration de l'application

```yaml
app:
  # Nombre de réplicas (1 recommandé pour homelab)
  replicaCount: 1
  
  # Image Docker
  image:
    repository: ghcr.io/gethomepage/homepage
    tag: latest  # Ou version spécifique : v0.8.0
    pullPolicy: IfNotPresent
  
  # Ressources allouées
  resources:
    requests:
      cpu: 100m      # CPU minimum garanti
      memory: 128Mi  # RAM minimum garantie
    limits:
      cpu: 500m      # CPU maximum autorisé
      memory: 512Mi  # RAM maximum autorisée
```

### Configuration du service

```yaml
service:
  type: ClusterIP  # ClusterIP, NodePort, ou LoadBalancer
  port: 3000       # Port d'écoute
```

### Configuration de l'ingress

```yaml
ingress:
  enabled: true
  className: traefik
  
  annotations:
    # Entrypoint HTTP (port 80)
    traefik.ingress.kubernetes.io/router.entrypoints: web
    
    # Pour HTTPS (nécessite certificat)
    # traefik.ingress.kubernetes.io/router.entrypoints: websecure
    # cert-manager.io/cluster-issuer: letsencrypt-prod
  
  hosts:
    - host: homepage.local  # Changez selon votre domaine
      paths:
        - path: /
          pathType: Prefix
  
  # Configuration TLS
  tls:
    enabled: false
    # Si enabled: true, ajoutez :
    # - secretName: homepage-tls
    #   hosts:
    #     - homepage.local
```

### Configuration du ServiceAccount

```yaml
serviceAccount:
  # Activer pour la découverte automatique des services K8s
  enabled: true
  
  # Nom personnalisé (optionnel)
  name: ""  # Si vide, utilise "homepage"
```

### Configuration de la persistence

```yaml
persistence:
  # Activer pour sauvegarder la configuration
  enabled: false
  
  # Classe de stockage (vide = default)
  storageClass: ""
  
  # Taille du volume
  size: 1Gi
  
  # Mode d'accès
  accessMode: ReadWriteOnce
```

**Note** : Si persistence est activée, la configuration du ConfigMap sera écrasée par les fichiers du PVC au premier démarrage. Ensuite, vous pourrez modifier la configuration directement dans l'interface homepage.

### Configuration de l'interface

```yaml
config:
  settings:
    title: "Homelab Dashboard"  # Titre affiché
    theme: dark                 # dark ou light
    color: slate                # slate, gray, zinc, neutral, stone, etc.
    headerStyle: boxed          # boxed, underlined, clean
```

### Labels et annotations personnalisés

```yaml
# Appliqués à toutes les ressources Kubernetes
customLabels:
  environment: "production"
  team: "homelab"

customAnnotations:
  monitoring: "enabled"
  backup: "daily"
```

## Exemples de configurations

### Configuration minimale (par défaut)

```yaml
app:
  replicaCount: 1
  image:
    repository: ghcr.io/gethomepage/homepage
    tag: latest

ingress:
  enabled: true
  hosts:
    - host: homepage.local

config:
  proxmox:
    enabled: false
```

### Configuration avec Proxmox et services personnalisés

```yaml
config:
  proxmox:
    enabled: true
    url: "https://192.168.1.200:8006"
    username: "root@pam!homepage"
    password: "votre-token"
  
  customServices:
    - name: "Infrastructure"
      services:
        - name: "Proxmox"
          icon: "proxmox.png"
          href: "https://192.168.1.200:8006"
          description: "Hyperviseur"
    
    - name: "Monitoring"
      services:
        - name: "Grafana"
          icon: "grafana.png"
          href: "http://grafana.local"
          description: "Dashboards"
```

### Configuration haute disponibilité

```yaml
app:
  replicaCount: 3  # 3 réplicas pour HA
  
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi

persistence:
  enabled: true
  storageClass: "nfs-client"  # Stockage partagé requis
  size: 5Gi
  accessMode: ReadWriteMany   # RWX pour multi-replica
```

### Configuration avec TLS

```yaml
ingress:
  enabled: true
  className: traefik
  
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    cert-manager.io/cluster-issuer: letsencrypt-prod
  
  hosts:
    - host: homepage.example.com
      paths:
        - path: /
          pathType: Prefix
  
  tls:
    enabled: true
    - secretName: homepage-tls
      hosts:
        - homepage.example.com
```

## Workflow de modification

1. **Éditer** le fichier `helm/homepage/values.yaml`
2. **Valider** localement :
   ```bash
   helm template homepage helm/homepage/ | kubectl apply --dry-run=client -f -
   ```
3. **Commit et push** :
   ```bash
   git add helm/homepage/values.yaml
   git commit -m "Update homepage configuration"
   git push
   ```
4. **Synchroniser** (automatique avec selfHeal, ou manuel) :
   ```bash
   argocd app sync homepage
   ```
5. **Vérifier** :
   ```bash
   kubectl get pods -n homepage
   kubectl logs -n homepage -l app.kubernetes.io/name=homepage
   ```

## Bonnes pratiques

### Sécurité

- **Ne commitez jamais de credentials** dans values.yaml
- Utilisez des **Sealed Secrets** ou **External Secrets** pour les données sensibles
- Préférez les **tokens API** aux mots de passe
- Activez **TLS** pour les déploiements en production

### Performance

- Ajustez les **resources requests/limits** selon votre charge
- Utilisez **imagePullPolicy: IfNotPresent** pour éviter les pulls inutiles
- Activez la **persistence** si vous modifiez souvent la configuration

### Maintenance

- Utilisez des **tags de version** spécifiques plutôt que `latest`
- Documentez vos **customServices** et **customWidgets**
- Testez les modifications avec `helm template` avant de commit

## Ressources supplémentaires

- [Documentation officielle Homepage](https://gethomepage.dev)
- [Liste des widgets disponibles](https://gethomepage.dev/en/widgets/)
- [Configuration des services](https://gethomepage.dev/en/configs/services/)
- [Guide de Maintenance](maintenance-guide.md)
- [Guide de Dépannage](troubleshooting-guide.md)
