# Guide de Maintenance - Homepage

Ce guide couvre les opérations de maintenance courantes pour le déploiement homepage : mises à jour, sauvegardes, et rollbacks.

## Mise à jour de l'image Homepage

### Vérifier la version actuelle

```bash
# Vérifier la version déployée
kubectl get deployment homepage -n homepage -o jsonpath='{.spec.template.spec.containers[0].image}'

# Vérifier les logs pour la version
kubectl logs -n homepage -l app.kubernetes.io/name=homepage | head -n 20
```

### Méthode 1 : Mise à jour vers latest (automatique)

Si vous utilisez `tag: latest` dans values.yaml, homepage se mettra à jour automatiquement :

```bash
# Forcer le pull de la nouvelle image
kubectl rollout restart deployment homepage -n homepage

# Suivre le déploiement
kubectl rollout status deployment homepage -n homepage

# Vérifier la nouvelle version
kubectl get pods -n homepage
kubectl logs -n homepage -l app.kubernetes.io/name=homepage | head -n 20
```

### Méthode 2 : Mise à jour vers une version spécifique (recommandé)

Pour un contrôle précis des versions :

1. **Vérifier les versions disponibles** :
   - Consultez [GitHub Releases](https://github.com/gethomepage/homepage/releases)
   - Ou [ghcr.io packages](https://github.com/gethomepage/homepage/pkgs/container/homepage)

2. **Modifier values.yaml** :

```yaml
app:
  image:
    repository: ghcr.io/gethomepage/homepage
    tag: v0.8.0  # Remplacez par la version souhaitée
    pullPolicy: IfNotPresent
```

3. **Appliquer la mise à jour** :

```bash
# Commit et push
git add helm/homepage/values.yaml
git commit -m "Update homepage to v0.8.0"
git push

# ArgoCD synchronisera automatiquement
# Ou forcer la synchronisation :
argocd app sync homepage

# Suivre le déploiement
kubectl rollout status deployment homepage -n homepage
```

### Vérifier la mise à jour

```bash
# Vérifier que le nouveau pod est Running
kubectl get pods -n homepage

# Vérifier les logs (pas d'erreurs)
kubectl logs -n homepage -l app.kubernetes.io/name=homepage --tail=50

# Tester l'accès web
curl -I http://homepage.local

# Vérifier l'interface
# Ouvrir http://homepage.local dans le navigateur
```

### Stratégie de mise à jour

Le déploiement utilise une stratégie **RollingUpdate** :

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0  # Aucun pod ne peut être indisponible
    maxSurge: 1        # Un pod supplémentaire pendant la mise à jour
```

**Comportement** :
1. Un nouveau pod est créé avec la nouvelle version
2. Le nouveau pod attend d'être Ready (readinessProbe)
3. Une fois Ready, l'ancien pod est terminé
4. Aucune interruption de service

## Sauvegarde de la configuration

### Sans persistence (ConfigMap uniquement)

La configuration est stockée dans Git, donc déjà sauvegardée :

```bash
# Sauvegarder le ConfigMap actuel (optionnel)
kubectl get configmap homepage-config -n homepage -o yaml > backup-configmap-$(date +%Y%m%d).yaml

# Sauvegarder values.yaml (déjà dans Git)
cp helm/homepage/values.yaml backup-values-$(date +%Y%m%d).yaml
```

### Avec persistence activée

Si vous avez activé la persistence, la configuration est dans un PVC :

```bash
# Identifier le PVC
kubectl get pvc -n homepage

# Créer un pod temporaire pour accéder au volume
kubectl run -it --rm backup-pod \
  --image=busybox \
  --restart=Never \
  --namespace=homepage \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "backup",
      "image": "busybox",
      "command": ["sh"],
      "stdin": true,
      "tty": true,
      "volumeMounts": [{
        "name": "config",
        "mountPath": "/config"
      }]
    }],
    "volumes": [{
      "name": "config",
      "persistentVolumeClaim": {
        "claimName": "homepage-config"
      }
    }]
  }
}' -- sh

# Dans le pod, créer une archive
tar czf /tmp/homepage-config-backup.tar.gz /config

# Depuis un autre terminal, copier l'archive
kubectl cp homepage/backup-pod:/tmp/homepage-config-backup.tar.gz \
  ./homepage-config-backup-$(date +%Y%m%d).tar.gz
```

### Sauvegarde automatique avec CronJob

Créez un CronJob pour sauvegarder automatiquement :

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: homepage-backup
  namespace: homepage
spec:
  schedule: "0 2 * * *"  # Tous les jours à 2h du matin
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: busybox
            command:
            - sh
            - -c
            - |
              tar czf /backup/homepage-config-$(date +%Y%m%d).tar.gz /config
              # Garder seulement les 7 dernières sauvegardes
              ls -t /backup/*.tar.gz | tail -n +8 | xargs rm -f
            volumeMounts:
            - name: config
              mountPath: /config
            - name: backup
              mountPath: /backup
          restartPolicy: OnFailure
          volumes:
          - name: config
            persistentVolumeClaim:
              claimName: homepage-config
          - name: backup
            persistentVolumeClaim:
              claimName: homepage-backup  # À créer
```

### Restaurer une sauvegarde

#### Restaurer depuis Git (ConfigMap)

```bash
# Revenir à une version précédente dans Git
git log --oneline helm/homepage/values.yaml
git checkout <commit-hash> helm/homepage/values.yaml

# Appliquer
git commit -m "Restore homepage configuration"
git push
argocd app sync homepage
```

#### Restaurer depuis un backup de PVC

```bash
# Créer un pod temporaire
kubectl run -it --rm restore-pod \
  --image=busybox \
  --restart=Never \
  --namespace=homepage \
  --overrides='<même config que backup-pod>' -- sh

# Copier l'archive dans le pod
kubectl cp ./homepage-config-backup-20240115.tar.gz \
  homepage/restore-pod:/tmp/backup.tar.gz

# Dans le pod, restaurer
cd /
tar xzf /tmp/backup.tar.gz

# Redémarrer homepage pour charger la config
kubectl rollout restart deployment homepage -n homepage
```

## Rollback via ArgoCD

### Rollback automatique (selfHeal)

ArgoCD est configuré avec `selfHeal: true`, donc il restaurera automatiquement l'état Git si des modifications manuelles sont faites.

### Rollback manuel vers une version précédente

#### Méthode 1 : Via Git

```bash
# Voir l'historique des commits
git log --oneline helm/homepage/

# Revenir à un commit spécifique
git revert <commit-hash>
# Ou
git reset --hard <commit-hash>
git push --force

# ArgoCD synchronisera automatiquement
```

#### Méthode 2 : Via ArgoCD CLI

```bash
# Voir l'historique des déploiements
argocd app history homepage

# Rollback vers une révision spécifique
argocd app rollback homepage <revision-id>

# Exemple : rollback vers la révision 5
argocd app rollback homepage 5
```

#### Méthode 3 : Via kubectl (rollback Kubernetes)

```bash
# Voir l'historique des rollouts
kubectl rollout history deployment homepage -n homepage

# Rollback vers la révision précédente
kubectl rollout undo deployment homepage -n homepage

# Rollback vers une révision spécifique
kubectl rollout undo deployment homepage -n homepage --to-revision=3

# Vérifier le rollback
kubectl rollout status deployment homepage -n homepage
```

### Vérifier après un rollback

```bash
# Vérifier l'état du pod
kubectl get pods -n homepage

# Vérifier les logs
kubectl logs -n homepage -l app.kubernetes.io/name=homepage --tail=50

# Vérifier la version de l'image
kubectl get deployment homepage -n homepage -o jsonpath='{.spec.template.spec.containers[0].image}'

# Tester l'accès web
curl -I http://homepage.local
```

## Maintenance du cluster

### Nettoyage des anciennes images

```bash
# Sur chaque node du cluster
docker image prune -a --filter "until=720h"  # Supprimer images > 30 jours

# Ou avec crictl (si vous utilisez containerd)
crictl rmi --prune
```

### Nettoyage des anciennes ReplicaSets

```bash
# Voir les anciennes ReplicaSets
kubectl get replicasets -n homepage

# Supprimer les ReplicaSets avec 0 pods
kubectl delete replicaset -n homepage -l app.kubernetes.io/name=homepage --field-selector 'status.replicas=0'
```

### Rotation des logs

Les logs Kubernetes sont automatiquement rotés, mais vous pouvez les archiver :

```bash
# Exporter les logs des 7 derniers jours
kubectl logs -n homepage -l app.kubernetes.io/name=homepage \
  --since=168h > homepage-logs-$(date +%Y%m%d).log

# Compresser
gzip homepage-logs-$(date +%Y%m%d).log
```

## Monitoring et alerting

### Vérifications de santé régulières

Créez un script de vérification :

```bash
#!/bin/bash
# check-homepage-health.sh

echo "=== Homepage Health Check ==="
echo

# Vérifier le pod
echo "Pod status:"
kubectl get pods -n homepage -l app.kubernetes.io/name=homepage

# Vérifier les ressources
echo -e "\nResource usage:"
kubectl top pod -n homepage -l app.kubernetes.io/name=homepage

# Vérifier l'accès HTTP
echo -e "\nHTTP check:"
curl -s -o /dev/null -w "Status: %{http_code}\nTime: %{time_total}s\n" http://homepage.local

# Vérifier les logs pour erreurs
echo -e "\nRecent errors:"
kubectl logs -n homepage -l app.kubernetes.io/name=homepage --tail=100 | grep -i error | tail -n 5

echo -e "\n=== Check complete ==="
```

### Configurer des alertes Prometheus

Si vous utilisez Prometheus, créez des alertes :

```yaml
groups:
- name: homepage
  rules:
  - alert: HomepagePodDown
    expr: kube_pod_status_phase{namespace="homepage",phase!="Running"} == 1
    for: 5m
    annotations:
      summary: "Homepage pod is not running"
  
  - alert: HomepageHighMemory
    expr: container_memory_usage_bytes{namespace="homepage"} > 400000000
    for: 10m
    annotations:
      summary: "Homepage memory usage > 400MB"
  
  - alert: HomepageNotAccessible
    expr: probe_success{job="homepage"} == 0
    for: 5m
    annotations:
      summary: "Homepage is not accessible via HTTP"
```


## Ressources supplémentaires

- [Guide de Déploiement](deployment-guide.md)
- [Guide de Configuration](configuration-guide.md)
- [Guide de Dépannage](troubleshooting-guide.md)
- [Documentation ArgoCD](https://argo-cd.readthedocs.io/)
- [Kubernetes Rollout Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
