#!/usr/bin/env bash
# Benchmark "Passage à l'échelle sur la taille des données"
# Produit out/post.csv au format :
# PARAM,AVG_TIME,RUN,FAILED
#
# PARAM = nombre de posts par utilisateur (10, 100, 1000)
# Concurrence fixée à 50, comme demandé par le prof.

set -euo pipefail

##############################################
# CONFIGURATION
##############################################

# URL de ton appli déployée
APP_URL="https://maximal-beach-473712-d1.ew.r.appspot.com"

# Concurrence fixée à 50 (consigne du prof)
CONCURRENCY=50

# Nombre total de requêtes par run
TOTAL_REQUESTS=500

# Paramètres (posts par utilisateur)
PARAM_LEVELS=(10 100 1000)

# Répertoires
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_DIR="$OUT_DIR/log_post"

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"

# Fichier CSV de sortie
CSV="$OUT_DIR/post.csv"

echo "Écriture dans $CSV"
echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"

##############################################
# Fonction pour choisir l'utilisateur selon PARAM
##############################################
get_user_for_param() {
  local param="$1"
  case "$param" in
    10)   echo "posts10_1" ;;
    100)  echo "posts100_1" ;;
    1000) echo "posts1000_1" ;;
    *)    echo "posts10_1" ;;  # fallback
  esac
}

##############################################
# Exécution des benchmarks
##############################################

for P in "${PARAM_LEVELS[@]}"; do
  echo ""
  echo "=== PARAM=$P posts/user (C=$CONCURRENCY) ==="

  USER="$(get_user_for_param "$P")"

  for RUN in 1 2 3; do
    echo "   ⏳ RUN $RUN (user=$USER)..."

    LOG="$LOG_DIR/post_P${P}_R${RUN}.log"

    FAILED=0
    AVG_MS=0

    # Lancer Apache Bench avec concurrence fixe à 50
    if ab -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" \
      "${APP_URL}/timeline?user=${USER}" >"$LOG" 2>&1; then

      AVG_MS=$(grep "Time per request:" "$LOG" | head -n 1 | awk '{print $4}')

      if [[ -z "$AVG_MS" ]]; then
        FAILED=1
        AVG_MS=0
        echo "  -> Impossible d'extraire le temps moyen, marqué FAILED=1"
      fi
    else
      FAILED=1
      AVG_MS=0
      echo "  -> 'ab' a échoué pour PARAM=$P RUN=$RUN. FAILED=1"
    fi

    echo "${P},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
  done
done

##############################################
echo "Benchmark POST terminé."
echo "➡ CSV généré : $CSV"
echo "➡ Logs disponibles dans : $LOG_DIR/"
