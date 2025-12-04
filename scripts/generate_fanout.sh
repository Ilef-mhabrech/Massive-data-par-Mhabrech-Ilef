#!/usr/bin/env bash
# ============================================================
# Benchmark fanout (fanout.csv)
# TinyInsta - Mhabrech Ilef 2025
#
# Objectif :
#   - 1000 users, 100 posts/user (≈ 100 000 posts)
#   - on NE SUPPRIME PAS les posts existants
#   - si < 100 000 posts -> on complète
#   - fanout = 10, 50, 100 (variation du nombre de followees)
#
# CSV : PARAM,AVG_TIME,RUN,FAILED
#   PARAM   = fanout (10, 50, 100)
#   AVG_TIME= temps moyen (ms)
#   RUN     = numéro de run (1..3)
#   FAILED  = 0 (ok) ou 1 (au moins une requête échouée)
# ============================================================

set -euo pipefail
shopt -s nullglob

###########################################
# CONFIG
###########################################

APP_URL="https://projectcloud-479410.ew.r.appspot.com"

MAX_USERS=1000
POSTS_PER_USER=100
TOTAL_POSTS=$(( MAX_USERS * POSTS_PER_USER ))

CONCURRENCY=50          # 50 utilisateurs concurrents
RUNS=3                  # 3 répétitions

FANOUT_LEVELS=(10 50 100)
DEFAULT_FANOUT=10       # utilisé uniquement quand on complète les posts

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_DIR="$OUT_DIR/log_fanout"
CSV="$OUT_DIR/fanout.csv"

SEED_SCRIPT="$ROOT_DIR/massive-gcp/seed.py"   # adapte le chemin si besoin

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"

if [[ ! -f "$CSV" ]]; then
  echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"
fi

echo "📁 Résultats fanout dans : $CSV"
echo "📂 Logs dans : $LOG_DIR"
echo
echo "🎯 Objectif : ${MAX_USERS} users, ${POSTS_PER_USER} posts/user (~${TOTAL_POSTS} posts)"
echo

###########################################
# Fonctions utilitaires
###########################################

count_posts() {
  python3 - << 'EOF'
from google.cloud import datastore

client = datastore.Client()
query = client.query(kind="Post")
query.keys_only()
print(sum(1 for _ in query.fetch()))
EOF
}

pick_random_users() {
  seq 1 "$MAX_USERS" | shuf | head -n "$CONCURRENCY"
}

###########################################
# Étape 0 : s'assurer qu'on a 100 000 posts
###########################################

echo "📊 Vérification initiale du nombre de posts…"
CURRENT_POSTS="$(count_posts)"
echo "   → Posts actuels : ${CURRENT_POSTS}"

if (( CURRENT_POSTS < TOTAL_POSTS )); then
  MISSING=$(( TOTAL_POSTS - CURRENT_POSTS ))
  echo "   ⚠ Il manque ${MISSING} posts pour atteindre ${TOTAL_POSTS}."
  echo "   ➕ Complétion des posts avec seed.py (sans suppression)…"

  python3 "$SEED_SCRIPT" \
    --users "$MAX_USERS" \
    --posts "$MISSING" \
    --follows-min "$DEFAULT_FANOUT" \
    --follows-max "$DEFAULT_FANOUT" \
    --prefix user

  CURRENT_POSTS="$(count_posts)"
  echo "   → Posts après complétion : ${CURRENT_POSTS}"

  if (( CURRENT_POSTS < TOTAL_POSTS )); then
    echo "   ❌ Après complétion, toujours moins de ${TOTAL_POSTS} posts. Abandon."
    exit 1
  fi

elif (( CURRENT_POSTS > TOTAL_POSTS )); then
  echo "   ⚠ Il y a déjà plus de ${TOTAL_POSTS} posts (${CURRENT_POSTS})."
  echo "   ❗ On ne supprime rien, on continue avec ce dataset."
else
  echo "   ✅ OK, il y a exactement ${TOTAL_POSTS} posts."
fi

echo

###########################################
# Boucle principale : variation du fanout
###########################################

for FANOUT in "${FANOUT_LEVELS[@]}"; do
  echo "==================================================="
  echo "➡️  FANOUT = ${FANOUT} followees par utilisateur"
  echo "    (on garde les mêmes posts : ${TOTAL_POSTS})"
  echo

  # 1) Reconfigurer les follows SANS toucher aux posts
  echo "🔁 Configuration des followees avec seed.py (posts=0)…"

  python3 "$SEED_SCRIPT" \
    --users "$MAX_USERS" \
    --posts 0 \
    --follows-min "$FANOUT" \
    --follows-max "$FANOUT" \
    --prefix user

  echo "   ✔ Suivis mis à jour pour FANOUT=${FANOUT}."
  echo

  # 2) Vérification de sécurité
  CURRENT_POSTS="$(count_posts)"
  echo "📊 Vérif : toujours ${CURRENT_POSTS} posts (on n'a rien supprimé)."
  echo

  # 3) Benchmark timeline
  echo "🚀 Benchmark timeline pour FANOUT=${FANOUT}…"

  for RUN in $(seq 1 "$RUNS"); do
    echo "--- FANOUT=${FANOUT} RUN=${RUN} ---"

    LOG_PREFIX="$LOG_DIR/F${FANOUT}_R${RUN}"
    FAILED=0
    AVG_MS=0

    mapfile -t USERS < <(pick_random_users)

    pids=()
    for U in "${USERS[@]}"; do
      USER_ID="user${U}"
      LOG_USER="${LOG_PREFIX}_u${U}.log"

      echo "   → ab pour ${USER_ID} (log: $(basename "$LOG_USER"))"

      ab -n 10 -c 1 \
        "${APP_URL}/api/timeline?user=${USER_ID}&limit=20" \
        >"$LOG_USER" 2>&1 &

      pids+=( "$!" )
    done

    # attendre la fin de tous les ab (on ignore le code retour ici)
    for pid in "${pids[@]}"; do
      wait "$pid" || true
    done

    files=( "${LOG_PREFIX}"_u*.log )

    if (( ${#files[@]} == 0 )); then
      echo "   ⚠ Aucun fichier de log pour FANOUT=${FANOUT} RUN=${RUN}"
      FAILED=1
      AVG_MS=0
    else
      # 1) Toujours calculer la moyenne des "Time per request"
      AVG_MS=$(
        grep -h "Time per request:" "${files[@]}" \
        | awk '{sum+=$4; n++} END { if (n>0) printf "%.3f", sum/n }'
      )

      if [[ -z "$AVG_MS" ]]; then
        echo "   ⚠ Impossible de lire 'Time per request' → FAILED=1"
        FAILED=1
        AVG_MS=0
      else
        # 2) Déterminer FAILED en fonction des "Failed requests"
        FAILED=0
        for f in "${files[@]}"; do
          # on exige "Failed requests: 0"
          if ! grep -q "Failed requests:[[:space:]]*0" "$f"; then
            FAILED=1
            break
          fi
        done
      fi
    fi

    echo "   → AVG_TIME=${AVG_MS} ms, FAILED=${FAILED}"
    echo "${FANOUT},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
    echo
  done

done

echo "✅ Bench fanout terminé. Résultats dans : $CSV"
