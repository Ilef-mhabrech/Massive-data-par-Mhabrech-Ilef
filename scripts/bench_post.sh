#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Benchmark "posts per user" pour TinyInsta
# - Concurrence fixée à 50
# - Followers = 20
# - Posts par user = 10, 100, 1000
# Résultat : out/post.csv
###############################################################################

# Chemins (projet racine = dossier parent de scripts/)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$BASE_DIR/out"
LOG_DIR="$OUT_DIR/logs_post"
CSV="$OUT_DIR/post.csv"

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

for POSTS in 10 100 1000; do
  PREFIX="posts${POSTS}"
  TIMELINE_USER="${PREFIX}1"

  echo
  echo "=== SEED: users=1000, posts=${POSTS}, follows=20, prefix=${PREFIX} ==="

  # On peuple la base pour ce scénario
  curl -s -X POST \
    -H "X-Seed-Token: ${SEED_TOKEN}" \
    "${APP_URL}/admin/seed?users=1000&posts=${POSTS}&follows_min=20&follows_max=20&prefix=${PREFIX}" \
    || echo "  (warning) seed call failed or already done"

  # 3 runs par configuration
  for RUN in 1 2 3; do
    echo "=== POSTS=${POSTS} RUN=${RUN} (c=${CONCURRENCY}) ==="
    LOG="${LOG_DIR}/ab_posts${POSTS}_run${RUN}.log"

    if ab -n "${TOTAL_REQUESTS}" -c "${CONCURRENCY}" \
         "${APP_URL}/api/timeline?user=${TIMELINE_USER}&limit=20" \
         > "${LOG}" 2>&1; then

      # On récupère "Time per request:  XXX [ms] (mean)"
      AVG_MS="$(grep 'Time per request:' "${LOG}" | head -n1 | awk '{print $4}')"

      if [[ -z "${AVG_MS}" ]]; then
        echo "  -> Impossible de parser le temps moyen, on marque FAILED=1"
        echo "${POSTS},0,${RUN},1" >> "${CSV}"
      else
        echo "  -> Temps moyen: ${AVG_MS} ms"
        echo "${POSTS},${AVG_MS},${RUN},0" >> "${CSV}"
      fi
    else
      echo "  -> 'ab' a échoué pour POSTS=${POSTS} RUN=${RUN}. FAILED=1"
      echo "${POSTS},0,${RUN},1" >> "${CSV}"
    fi
  done
done

echo
echo "Benchmark POST terminé. Résultats dans ${CSV}"
