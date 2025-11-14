#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Benchmark "fanout" pour TinyInsta
# - Concurrence fixée à 50
# - Posts par user = 100
# - Followees par user = 10, 50, 100
# Résultat : out/fanout.csv
###############################################################################

# Chemins (projet racine = dossier parent de scripts/)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$BASE_DIR/out"
LOG_DIR="$OUT_DIR/logs_fanout"
CSV="$OUT_DIR/fanout.csv"

mkdir -p "$OUT_DIR" "$LOG_DIR"

# URL de ton appli GAE
APP_URL="https://maximal-beach-473712-d1.ew.r.appspot.com"

# Token de seed (même que dans le README du prof)
SEED_TOKEN="change-me-seed-token"

# Paramètres ApacheBench
CONCURRENCY=50        # nombre d'utilisateurs concurrents
TOTAL_REQUESTS=500    # nb total de requêtes par run

# Fichier CSV de sortie
echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"

# posts par user fixé à 100
POSTS_PER_USER=100

for FOLLOWS in 10 50 100; do
  # Préfixe pour différencier les datasets
  PREFIX="fanout${FOLLOWS}_"
  TIMELINE_USER="${PREFIX}1"   # ex: fanout10_1

  echo
  echo "=== SEED: users=1000, posts=${POSTS_PER_USER}, follows=${FOLLOWS}, prefix=${PREFIX} ==="

  # On peuple la base pour ce scénario
  curl -s -X POST \
    -H "X-Seed-Token: ${SEED_TOKEN}" \
    "${APP_URL}/admin/seed?users=1000&posts=${POSTS_PER_USER}&follows_min=${FOLLOWS}&follows_max=${FOLLOWS}&prefix=${PREFIX}" \
    || echo "  (warning) seed call failed or already done"

  # 3 runs par configuration
  for RUN in 1 2 3; do
    echo "=== FOLLOWS=${FOLLOWS} RUN=${RUN} (c=${CONCURRENCY}) ==="
    LOG="${LOG_DIR}/ab_fanout${FOLLOWS}_run${RUN}.log"

    if ab -n "${TOTAL_REQUESTS}" -c "${CONCURRENCY}" \
         "${APP_URL}/api/timeline?user=${TIMELINE_USER}&limit=20" \
         > "${LOG}" 2>&1; then

      # On récupère "Time per request:  XXX [ms] (mean)"
      AVG_MS="$(grep 'Time per request:' "${LOG}" | head -n1 | awk '{print $4}')"

      if [[ -z "${AVG_MS}" ]]; then
        echo "  -> Impossible de parser le temps moyen, on marque FAILED=1"
        echo "${FOLLOWS},0,${RUN},1" >> "${CSV}"
      else
        echo "  -> Temps moyen: ${AVG_MS} ms"
        echo "${FOLLOWS},${AVG_MS},${RUN},0" >> "${CSV}"
      fi
    else
      echo "  -> 'ab' a échoué pour FOLLOWS=${FOLLOWS} RUN=${RUN}. FAILED=1"
      echo "${FOLLOWS},0,${RUN},1" >> "${CSV}"
    fi
  done
done

echo
echo "Benchmark FANOUT terminé. Résultats dans ${CSV}"
