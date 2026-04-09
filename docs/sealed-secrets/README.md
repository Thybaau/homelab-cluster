# Sealed Secrets

Contrôleur de chiffrement des secrets Kubernetes, permettant de stocker des secrets dans Git de manière sécurisée.

## Rôle

Sealed Secrets résout le problème du stockage de secrets dans un workflow GitOps. Les secrets sont chiffrés côté client avec `kubeseal` (clé publique), stockés dans Git sous forme de `SealedSecret`, puis déchiffrés automatiquement dans le cluster par le contrôleur.

## Configuration

| Paramètre | Valeur |
|---|---|
| Chart | `bitnami-labs/sealed-secrets` v2.13.2 |
| Namespace | `sealed-secrets` |
| Sync wave | 0 (déployé en premier, avant les apps qui en dépendent) |

## Flux de fonctionnement

```
kubeseal --cert pub-cert.pem < secret.yaml > sealedsecret.yaml
    │
    ▼
SealedSecret dans Git → ArgoCD sync → Sealed Secrets Controller
                                              │
                                        Déchiffrement
                                              │
                                        Secret Kubernetes
```

## Secrets gérés dans le cluster

| SealedSecret | Namespace | Utilisé par |
|---|---|---|
| `valhafin-db-credentials` | `valhafin` | PostgreSQL (user, password, db) |
| `valhafin-backend-secrets` | `valhafin` | Backend Go (clé AES-256) |
| `grafana-admin-credentials` | `monitoring` | Grafana (admin user/password) |
| `cloudflare-tunnel-token` | `networking` | Cloudflared (token tunnel) |

## Utilisation

Voir le guide détaillé : [Sealed Secrets pour Valhafin](../valhafin-sealed-secrets.md)

```bash
# Récupérer la clé publique du cluster
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets > pub-cert.pem

# Chiffrer un secret
kubeseal --format=yaml --cert=pub-cert.pem < secret.yaml > sealedsecret.yaml
```

## Backup des clés privées

Le contrôleur Sealed Secrets génère des clés de chiffrement automatiquement (rotation tous les 30 jours par défaut). Si le cluster est reconstruit sans restaurer ces clés, tous les SealedSecrets existants dans Git deviennent inutilisables.

**Script de backup :**

```bash
./scripts/backup-sealed-secrets-keys.sh [dossier_destination]
```

Le script exporte toutes les clés privées dans un fichier YAML daté avec permissions `600`. Transférer le fichier dans un gestionnaire de mots de passe (Bitwarden, 1Password, etc.) puis supprimer le fichier local.

**Restauration :**

```bash
kubectl apply -f sealed-secrets-keys-backup-YYYY-MM-DD_HHMMSS.yaml
# Redémarrer le contrôleur pour charger les clés restaurées
kubectl rollout restart deployment sealed-secrets -n sealed-secrets
```

⚠️ Ne JAMAIS stocker le fichier de backup dans Git.

## Fichiers

- Manifest ArgoCD : [`argocd-apps/sealed-secrets-app.yml`](../argocd-apps/sealed-secrets-app.yml)
- Pas de chart local — chart officiel Bitnami déployé directement
