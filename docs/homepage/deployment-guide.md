# Guide de Déploiement - Homepage

Ce guide détaille les étapes pour déployer homepage.dev dans votre cluster Kubernetes homelab via ArgoCD.

## Prérequis

Avant de déployer homepage, assurez-vous que les éléments suivants sont en place :

### Infrastructure requise

- **Cluster Kubernetes** : Version 1.20 ou supérieure
- **ArgoCD** : Installé et configuré dans le namespace `argocd`
- **Traefik** : Ingress Controller installé et fonctionnel
- **kubectl** : CLI configuré pour accéder au cluster
- **Git** : Accès au repository `https://github.com/Thybaau/homelab-cluster.git`

### Ressources minimales

Le déploiement homepage nécessite :
- **CPU** : 100m (request), 500m (limit)
- **Mémoire** : 128Mi (request), 512Mi (limit)
- **Stockage** : Optionnel, 1Gi si persistence activée

### Permissions

- Accès en écriture au namespace `argocd` pour créer l'Application
- ArgoCD doit avoir les permissions pour créer le namespace `homepage`
- ArgoCD doit pouvoir créer des ClusterRole et ClusterRoleBinding

## Installation via ArgoCD

### Étape 1 : Vérifier le repository Git

Assurez-vous que le repository est accessible et contient les fichiers nécessaires :

```bash
# Cloner le repository (si pas déjà fait)
git clone https://github.com/Thybaau/homelab-cluster.git
cd homelab-cluster

# Vérifier la présence du Helm chart
ls -la helm/homepage/

# Vérifier la présence de l'application ArgoCD
ls -la argocd-apps/homepage-app.yml
```

### Étape 2 : Appliquer l'application ArgoCD

Déployez l'application ArgoCD qui gérera le déploiement de homepage :

```bash
# Appliquer le manifest ArgoCD
kubectl apply -f argocd-apps/homepage-app.yml

# Vérifier que l'application est créée
kubectl get application homepage -n argocd
```

Sortie attendue :
```
NAME       SYNC STATUS   HEALTH STATUS
homepage   Synced        Healthy
```

### Étape 3 : Surveiller la synchronisation

ArgoCD va automatiquement synchroniser l'application. Vous pouvez suivre la progression :

```bash
# Via kubectl
kubectl get application homepage -n argocd -w

# Via ArgoCD CLI (si installé)
argocd app get homepage

# Suivre les événements
kubectl get events -n homepage --sort-by='.lastTimestamp'
```

### Étape 4 : Vérifier le déploiement

Une fois la synchronisation terminée, vérifiez que toutes les ressources sont créées :

```bash
# Vérifier le namespace
kubectl get namespace homepage

# Vérifier toutes les ressources
kubectl get all -n homepage

# Vérifier les ressources RBAC
kubectl get serviceaccount,clusterrole,clusterrolebinding | grep homepage

# Vérifier le ConfigMap
kubectl get configmap -n homepage

# Vérifier l'Ingress
kubectl get ingress -n homepage
```

Sortie attendue :
```
NAME                           READY   STATUS    RESTARTS   AGE
pod/homepage-xxxxxxxxxx-xxxxx  1/1     Running   0          2m

NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/homepage   ClusterIP   10.43.xxx.xxx   <none>        3000/TCP   2m

NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/homepage   1/1     1            1           2m

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/homepage-xxxxxxxxxx  1         1         1       2m
```

## Configuration DNS

Pour accéder à homepage via l'URL `homepage.local`, vous devez configurer la résolution DNS.

### Option 1 : Fichier /etc/hosts (recommandé pour homelab)

Ajoutez une entrée dans votre fichier `/etc/hosts` :

```bash
# Obtenir l'IP du cluster (remplacez par votre IP)
CLUSTER_IP="192.168.1.100"

# Ajouter l'entrée (nécessite sudo)
echo "$CLUSTER_IP homepage.local" | sudo tee -a /etc/hosts
```

### Option 2 : DNS local (Pi-hole, dnsmasq, etc.)

Si vous utilisez un serveur DNS local, ajoutez un enregistrement A :

```
homepage.local. IN A 192.168.1.100
```

### Option 3 : Accès direct via port-forward (temporaire)

Pour un accès temporaire sans configuration DNS :

```bash
kubectl port-forward -n homepage svc/homepage 3000:3000
```

Puis accédez à `http://localhost:3000`

## Vérification du déploiement

### Test 1 : Vérifier l'état des pods

```bash
# Vérifier que le pod est Running
kubectl get pods -n homepage

# Vérifier les logs (ne doit pas contenir d'erreurs)
kubectl logs -n homepage -l app.kubernetes.io/name=homepage
```

### Test 2 : Vérifier la connectivité interne

```bash
# Tester l'accès au service depuis le cluster
kubectl run -it --rm test-curl --image=curlimages/curl --restart=Never -- \
  curl -f http://homepage.homepage.svc.cluster.local:3000
```

Sortie attendue : Code HTML de la page homepage

### Test 3 : Vérifier l'Ingress

```bash
# Vérifier la configuration de l'Ingress
kubectl describe ingress homepage -n homepage

# Vérifier que Traefik a créé la route
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik | grep homepage
```

### Test 4 : Accéder à l'interface web

Ouvrez votre navigateur et accédez à :

```
http://homepage.local
```

Vous devriez voir le dashboard homepage avec :
- Le titre "Homelab Dashboard"
- Le thème sombre (dark)
- Les widgets système (CPU, RAM, disque)
- La section Infrastructure avec le widget Proxmox

### Test 5 : Vérifier les permissions RBAC

```bash
# Vérifier que le ServiceAccount peut lister les pods
kubectl auth can-i list pods --as=system:serviceaccount:homepage:homepage

# Vérifier que le ServiceAccount ne peut pas créer de pods (read-only)
kubectl auth can-i create pods --as=system:serviceaccount:homepage:homepage
```

Sortie attendue :
```
yes
no
```

## Dépannage rapide

### Le pod ne démarre pas

```bash
# Vérifier les événements
kubectl describe pod -n homepage -l app.kubernetes.io/name=homepage

# Vérifier les logs
kubectl logs -n homepage -l app.kubernetes.io/name=homepage
```

### L'Ingress n'est pas accessible

```bash
# Vérifier que Traefik fonctionne
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Vérifier la configuration de l'Ingress
kubectl get ingress homepage -n homepage -o yaml

# Tester avec port-forward
kubectl port-forward -n homepage svc/homepage 3000:3000
```

### ArgoCD ne synchronise pas

```bash
# Vérifier l'état de l'application
argocd app get homepage

# Forcer une synchronisation
argocd app sync homepage

# Vérifier les logs ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

## Prochaines étapes

Une fois le déploiement réussi :

1. **Configuration** : Consultez le [Guide de Configuration](configuration-guide.md) pour personnaliser homepage
2. **Maintenance** : Consultez le [Guide de Maintenance](maintenance-guide.md) pour les mises à jour
3. **Dépannage** : Consultez le [Guide de Dépannage](troubleshooting-guide.md) pour les problèmes courants

## Désinstallation

Pour supprimer homepage du cluster :

```bash
# Supprimer l'application ArgoCD (supprime toutes les ressources)
kubectl delete application homepage -n argocd

# Vérifier que le namespace est supprimé
kubectl get namespace homepage

# Supprimer manuellement si nécessaire
kubectl delete namespace homepage

# Nettoyer les ressources RBAC
kubectl delete clusterrole homepage
kubectl delete clusterrolebinding homepage
```
