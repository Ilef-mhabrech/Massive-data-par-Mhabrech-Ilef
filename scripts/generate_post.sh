#!/usr/bin/env bash
# ============================================================
# Benchmark fanout (fanout.csv)
# TinyInsta - Mhabrech Ilef 2025
#
# Objectif : 1000 users, 100 posts/user (≈ 100 000 posts)
# et fanout = 10, 50, 100.
#
# Pour chaque fanout :
#   - efface tous les Post
#   - reseed : 1000 users, 100 posts/user, followees = fanout
#   - vérifie qu'on a bien 100 000 posts (sinon on reseed encore)
#   - lance un bench timeline avec 50 users concurrents
#   - écrit dans out/fanout.csv : PARAM,AVG_TIME,RUN,FAILED
#     FAILED est toujours 0 ou 1.
# ============================================================

set -euo pipefail
shopt -s nullglob

###########################################
# CONFIG
###########################################

APP_URL="https://projectcloud-479410.ew.r.appspot.com"

MAX_USERS=1000          # nombre d'utilisateurs
POSTS_PER_USER=100      # 100 posts par utilisateur
TOTAL_POSTS=$(( MAX_USERS * POSTS_PER_USER ))

CONCURRENCY=50          # 50 utilisateurs concurrents
RUNS=3                  # 3 répétitions

FANOUT_LEVELS=(10 50 100)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_DIR="$OUT_DIR/log_fanout"
CSV="$OUT_DIR/fanout.csv"

SEED_SCRIPT="$ROOT_DIR/massive-gcp/seed.py"   # adapte ce chemin si besoin

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"

# Création du CSV si inexistant
if [[ ! -f "$CSV" ]]; then
  echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"
fi

echo "📁 Résultats fanout dans : $CSV"
echo "📂 Logs dans : $LOG_DIR"
echo
echo "🎯 Objectif de données : ${MAX_USERS} users, ${POSTS_PER_USER} posts/user (~${TOTAL_POSTS} posts au total)"
echo

###########################################
# Fonctions utilitaires
###########################################

# Effacer tous les posts
delete_all_posts() {
  echo "🧹 Suppression de tous les posts (en batch)…"

  python3 - << 'EOF'
from google.cloud import datastore

client = datastore.Client()
batch_size = 500
total_deleted = 0

while True:
    query = client.query(kind="Post")
    query.keys_only()
    entities = list(query.fetch(limit=batch_size))
    if not entities:
        break
    client.delete_multi([e.key for e in entities])
    total_deleted += len(entities)
    print(f"   → Batch supprimé : {len(entities)} posts (total = {total_deleted})")

print(f"[Delete] Terminé, posts supprimés = {total_deleted}")
EOF
}

# Compter les posts dans le Datastore
count_posts() {
  python3 - << 'EOF'
from google.cloud import datastore

client = datastore.Client()
query = client.query(kind="Post")
query.keys_only()
print(sum(1 for _ in query.fetch()))
EOF
}

# Choisir CONCURRENCY users aléatoires parmi 1..MAX_USERS
pick_random_users() {
  seq 1 "$MAX_USERS" | shuf | head -n "$CONCURRENCY"
}

###########################################
# Boucle principale : fanout = 10, 50, 100
###########################################
for FANOUT in "${FANOUT_LEVELS[@]}"; do
  echo "==================================================="
  echo "➡️  FANOUT = ${FANOUT} followees par utilisateur"
  echo "    (1000 users, ${POSTS_PER_USER} posts/user)"
  echo

  # 1) Effacer tous les posts
  delete_all_posts
  echo

  # 2) Seed initial
  echo "🌱 Seed des données : ${MAX_USERS} users, ~${POSTS_PER_USER} posts/user, fanout=${FANOUT}…"

  python3 "$SEED_SCRIPT" \
    --users "$MAX_USERS" \
    --posts "$TOTAL_POSTS" \
    --follows-min "$FANOUT" \
    --follows-max "$FANOUT" \
    --prefix user

  echo "   ✔ Seed terminé."
  echo

  # 3) Vérification : on veut EXACTEMENT TOTAL_POSTS
  echo "📊 Vérification du nombre de posts…"
  CURRENT_POSTS="$(count_posts)"
  echo "   → Posts actuels : ${CURRENT_POSTS}"

  if (( CURRENT_POSTS != TOTAL_POSTS )); then
    echo "   ⚠ On attend ${TOTAL_POSTS} posts, mais il y en a ${CURRENT_POSTS}."
    echo "   🔁 On reset & reseed une seconde fois…"
    delete_all_posts

    python3 "$SEED_SCRIPT" \
      --users "$MAX_USERS" \
      --posts "$TOTAL_POSTS" \
      --follows-min "$FANOUT" \
      --follows-max "$FANOUT" \
      --prefix user

    CURRENT_POSTS="$(count_posts)"
    echo "   → Posts après reseed : ${CURRENT_POSTS}"

    if (( CURRENT_POSTS != TOTAL_POSTS )); then
      echo "   ❌ Impossible d'obtenir exactement ${TOTAL_POSTS} posts. On arrête."
      exit 1
    fi
  fi

  echo "   ✅ OK, on a bien ${TOTAL_POSTS} posts."
  echo

  # 4) BENCHMARK timeline
  echo "🚀 Benchmark timeline pour FANOUT=${FANOUT}…"

  for RUN in $(seq 1 "$RUNS"); do
    echo "--- FANOUT=${FANOUT} RUN=${RUN} ---"

    LOG_PREFIX="$LOG_DIR/F${FANOUT}_R${RUN}"
    FAILED=0
    AVG_MS=0

    # choisir 50 users aléatoires
    mapfile -t USERS < <(pick_random_users)

    pids=()
    for U in "${USERS[@]}"; do
      USER_ID="user${U}"
      LOG_USER="${LOG_PREFIX}_u${U}.log"

      echo "   → ab pour ${USER_ID} (log: $(basename "$LOG_USER"))"

      # 10 requêtes par user, sérialisées (c=1)
      ab -n 10 -c 1 \
        "${APP_URL}/api/timeline?user=${USER_ID}&limit=20" \
        >"$LOG_USER" 2>&1 &

      pids+=( "$!" )
    done

    # attendre que tous les ab se terminent
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        FAILED=1
      fi
    done

    # calcul du temps moyen si tout s’est bien passé
    if (( FAILED == 0 )); then
      files=( "${LOG_PREFIX}"_u*.log )

      if (( ${#files[@]} > 0 )); then
        AVG_MS=$(
          grep -h "Time per request:" "${files[@]}" \
          | awk '{sum+=$4; n++} END { if (n>0) printf "%.3f", sum/n }'
        )

        if [[ -z "$AVG_MS" ]]; then
          echo "   ⚠ Impossible de lire 'Time per request' → FAILED=1"
          FAILED=1
          AVG_MS=0
        fi
      else
        echo "   ⚠ Aucun fichier de log pour FANOUT=${FANOUT} RUN=${RUN}"
        FAILED=1
        AVG_MS=0
      fi
    else
      echo "   ⚠ Au moins un 'ab' a échoué pour FANOUT=${FANOUT} RUN=${RUN}"
      AVG_MS=0
    fi

    # Ici FAILED est forcément 0 ou 1
    echo "   → AVG_TIME=${AVG_MS} ms, FAILED=${FAILED}"
    echo "${FANOUT},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
    echo
  done

done

echo "✅ Bench fanout terminé. Résultats dans : $CSV"
