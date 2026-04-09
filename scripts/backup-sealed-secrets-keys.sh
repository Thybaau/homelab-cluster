#!/usr/bin/env bash
# backup-sealed-secrets-keys.sh
# Exporte les clés privées du contrôleur Sealed Secrets dans un fichier daté.
# Usage: ./scripts/backup-sealed-secrets-keys.sh [output_dir]
#
# IMPORTANT: Le fichier exporté contient des clés privées.
#            Ne JAMAIS le stocker dans Git.
#            Le transférer dans un gestionnaire de mots de passe sécurisé.

set -euo pipefail

NAMESPACE="${SS_NAMESPACE:-sealed-secrets}"
OUTPUT_DIR="${1:-$(pwd)}"

# Vérifier que le dossier de destination existe
if [ ! -d "${OUTPUT_DIR}" ]; then
  echo "❌ Le dossier '${OUTPUT_DIR}' n'existe pas." >&2
  exit 1
fi

DATE=$(date +%Y-%m-%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/sealed-secrets-keys-backup-${DATE}.yaml"

# Restreindre les permissions des fichiers créés
umask 077

# Vérifier que kubectl est disponible et connecté
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Impossible de se connecter au cluster Kubernetes." >&2
  echo "   Vérifiez votre KUBECONFIG et votre connexion." >&2
  exit 1
fi

# Vérifier que le namespace existe
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "❌ Le namespace '${NAMESPACE}' n'existe pas." >&2
  echo "   Vérifiez que Sealed Secrets est installé." >&2
  exit 1
fi

# Exporter les clés
echo "🔑 Export des clés Sealed Secrets depuis le namespace '${NAMESPACE}'..."
kubectl get secret -n "${NAMESPACE}" \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > "${OUTPUT_FILE}"

# Vérifier que le fichier contient des clés (pas juste un items: [] vide)
if [ ! -s "${OUTPUT_FILE}" ] || ! grep -q "sealedsecrets.bitnami.com/sealed-secrets-key" "${OUTPUT_FILE}"; then
  echo "⚠️  Aucune clé trouvée. Le contrôleur Sealed Secrets est-il installé ?" >&2
  rm -f "${OUTPUT_FILE}"
  exit 1
fi

echo "✅ Backup créé : ${OUTPUT_FILE}"
echo "📋 Prochaines étapes :"
echo "   1. Transférer ce fichier dans un gestionnaire de mots de passe (Bitwarden, 1Password, etc.)"
echo "   2. Supprimer le fichier local après transfert"
echo "   3. Ne JAMAIS committer ce fichier dans Git"
