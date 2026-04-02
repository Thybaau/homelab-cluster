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

## Fichiers

- Manifest ArgoCD : [`argocd-apps/sealed-secrets-app.yml`](../argocd-apps/sealed-secrets-app.yml)
- Pas de chart local — chart officiel Bitnami déployé directement
