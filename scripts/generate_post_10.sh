#!/usr/bin/env bash
# ============================================================
# Benchmark taille des données (post.csv)
# TinyInsta - Mhabrech Ilef 2025 
# ============================================================

set -euo pipefail

APP_URL="https://projectcloud-479410.ew.r.appspot.com"
MAX_USERS=1000
FOLLOWERS=20
CONCURRENCY=50
RUNS=3

# 🔽 ICI : on remonte d’un dossier pour utiliser la racine du projet
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_DIR="$OUT_DIR/log_post"
CSV="$OUT_DIR/post.csv"

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"

# Première création du CSV si inexistant
if [[ ! -f "$CSV" ]]; then
    echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"
fi

# ============================================================
# Vérifier argument : nombre de posts/user
# ============================================================
if [[ $# -ne 1 ]]; then
    echo "Usage : bash generate_post.sh <POSTS_PER_USER>"
    exit 1
fi

POSTS_PER_USER=$1
echo "➡️  Benchmark avec $POSTS_PER_USER posts/user"

# ============================================================
# 1) SUPPRIMER LES POSTS EXISTANTS
# ============================================================
echo "🧹 Suppression des posts existants…"

python3 - <<EOF
from google.cloud import datastore

client = datastore.Client()
query = client.query(kind="Post")
keys = [entity.key for entity in query.fetch()]

if keys:
    client.delete_multi(keys)
    print(f"Supprimé {len(keys)} posts.")
else:
    print("Aucun post à supprimer.")
EOF

# 2) RESEED : créer les nouveaux posts
echo "🌱 Seed des données : $MAX_USERS users, $POSTS_PER_USER posts/user…"

# ICI : on convertit "posts par user" en "posts totaux" pour seed.py
TOTAL_POSTS=$(( POSTS_PER_USER * MAX_USERS ))

python3 ../massive-gcp/seed.py \
  --users "$MAX_USERS" \
  --posts "$TOTAL_POSTS" \
  --follows-min "$FOLLOWERS" \
  --follows-max "$FOLLOWERS" \
  --prefix user


# ============================================================
# 3) BENCHMARK (50 users simultanés)
# ============================================================
echo "🚀 Benchmark…"

pick_random_users() {
  seq 1 "$MAX_USERS" | shuf | head -n "$CONCURRENCY"
}

for RUN in $(seq 1 $RUNS); do
    echo "=== RUN $RUN ==="

    LOG_PREFIX="$LOG_DIR/P${POSTS_PER_USER}_R${RUN}"
    FAILED=0
    AVG_MS=0

    mapfile -t USERS < <(pick_random_users)

    pids=()
    for U in "${USERS[@]}"; do
      USER_ID="user${U}"
      LOG_USER="${LOG_PREFIX}_u${U}.log"

      ab -n 10 -c 1 \
       "${APP_URL}/api/timeline?user=${USER_ID}&limit=20" >"$LOG_USER" 2>&1 &
      pids+=( "$!" )
    done

    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        FAILED=1
      fi
    done

    if (( FAILED == 0 )); then
      files=( "${LOG_PREFIX}"_u*.log )
      AVG_MS=$(grep -h "Time per request:" "${files[@]}" |
               awk '{sum+=$4; n++} END { if (n>0) printf "%.3f", sum/n }')
      [[ -z "$AVG_MS" ]] && FAILED=1 && AVG_MS=0
    fi

    echo "${POSTS_PER_USER},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
done

echo "✨ Terminé ! Résultats ajoutés dans $CSV"
echo "📂 Fichier : $CSV"
