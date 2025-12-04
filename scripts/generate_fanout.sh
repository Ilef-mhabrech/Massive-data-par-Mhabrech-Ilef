#!/usr/bin/env bash
# ============================================================
# Benchmark variation du fanout (fanout.csv)
# TinyInsta - Mhabrech Ilef 2025
# - Posts par user fixés à 100  => 100 000 posts au total
# - On varie le nombre de followees : 10, 50, 100
# ============================================================

set -euo pipefail

APP_URL="https://projectcloud-479410.ew.r.appspot.com"

MAX_USERS=1000
POSTS_PER_USER=100
TARGET_POSTS=$(( MAX_USERS * POSTS_PER_USER ))   # 100 000 posts

CONCURRENCY=50        # 50 utilisateurs concurrents
RUNS=3               # 3 répétitions
FANOUT_LEVELS=(10 50 100)

# On remonte d’un dossier pour utiliser la racine du projet
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_DIR="$OUT_DIR/log_fanout"
CSV="$OUT_DIR/fanout.csv"

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"

# Création du CSV si nécessaire
if [[ ! -f "$CSV" ]]; then
    echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"
fi

# ============================================================
# 1) Fonction : s’assurer qu’on a ~100 000 posts
#    - si > 100 000 : on supprime juste l’excès
#    - si < 100 000 : on crée les posts manquants avec seed.py
# ============================================================
ensure_posts() {
  echo "📊 Vérification / ajustement des posts (objectif = ${TARGET_POSTS})…"

  CURRENT_POSTS=$(
python3 - << 'EOF'
from google.cloud import datastore

client = datastore.Client()
query = client.query(kind="Post")
count = sum(1 for _ in query.fetch())
print(count)
EOF
  )

  echo "   → Posts actuels dans Datastore : ${CURRENT_POSTS}"

  if (( CURRENT_POSTS > TARGET_POSTS )); then
    EXCESS=$(( CURRENT_POSTS - TARGET_POSTS ))
    echo "   → ${EXCESS} posts en trop, suppression des posts excédentaires…"

python3 - << EOF
from google.cloud import datastore

TARGET = ${TARGET_POSTS}
client = datastore.Client()
query = client.query(kind="Post")

# On récupère toutes les clés
keys = [e.key for e in query.fetch()]
current = len(keys)
excess = current - TARGET

if excess > 0:
    to_delete = keys[:excess]
    BATCH_SIZE = 500
    for i in range(0, len(to_delete), BATCH_SIZE):
        batch = to_delete[i:i+BATCH_SIZE]
        client.delete_multi(batch)
    print(f"Supprimé {excess} posts excédentaires.")
else:
    print("Aucun post excédentaire à supprimer.")
EOF

  elif (( CURRENT_POSTS < TARGET_POSTS )); then
    MISSING=$(( TARGET_POSTS - CURRENT_POSTS ))
    echo "   → Il manque ${MISSING} posts, création avec seed.py…"

    BATCH_SIZE=50000
    REMAINING=$MISSING

    while (( REMAINING > 0 )); do
      if (( REMAINING > BATCH_SIZE )); then
        BATCH=$BATCH_SIZE
      else
        BATCH=$REMAINING
      fi

      echo "      → Seed batch de ${BATCH} posts (reste $((REMAINING - BATCH)))…"

      python3 "${ROOT_DIR}/massive-gcp/seed.py" \
        --users "$MAX_USERS" \
        --posts "$BATCH" \
        --follows-min 20 \
        --follows-max 20 \
        --prefix user

      REMAINING=$(( REMAINING - BATCH ))
    done
  else
    echo "   → Nombre de posts déjà correct."
  fi

  # Récap final
  FINAL_POSTS=$(
python3 - << 'EOF'
from google.cloud import datastore

client = datastore.Client()
query = client.query(kind="Post")
count = sum(1 for _ in query.fetch())
print(count)
EOF
  )

  echo "   → Posts après ajustement : ${FINAL_POSTS}"
}

# ============================================================
# 2) Utilitaire : choisir 50 users aléatoires pour le benchmark
# ============================================================
pick_random_users() {
  seq 1 "$MAX_USERS" | shuf | head -n "$CONCURRENCY"
}

# ============================================================
# 3) MAIN
# ============================================================

# On s’assure qu’on a ~100 000 posts avant de jouer sur le fanout
ensure_posts

for F in "${FANOUT_LEVELS[@]}"; do
  echo "============================================"
  echo "⭐ Benchmark fanout = ${F} followees par user"
  echo "============================================"

  echo "🔄 Mise à jour des followees via seed.py (sans créer de nouveaux posts)…"
  # --posts 0 : on ne crée pas de posts en plus, on ne fait qu’ajuster les relations de suivi
  python3 "${ROOT_DIR}/massive-gcp/seed.py" \
    --users "$MAX_USERS" \
    --posts 0 \
    --follows-min "$F" \
    --follows-max "$F" \
    --prefix user

  # ------- Bench pour ce niveau de fanout -------
  for RUN in $(seq 1 "$RUNS"); do
    echo "--- RUN ${RUN} (fanout=${F}) ---"

    LOG_PREFIX="${LOG_DIR}/F${F}_R${RUN}"
    FAILED=0
    AVG_MS=0

    mapfile -t USERS < <(pick_random_users)

    pids=()
    for U in "${USERS[@]}"; do
      USER_ID="user${U}"
      LOG_USER="${LOG_PREFIX}_u${U}.log"

      ab -n 10 -c 1 \
        "${APP_URL}/api/timeline?user=${USER_ID}&limit=20" > "$LOG_USER" 2>&1 &

      pids+=( "$!" )
    done

    # On attend tous les ab
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        FAILED=1
      fi
    done

    # Calcul du temps moyen si tout est OK
    if (( FAILED == 0 )); then
      files=( "${LOG_PREFIX}"_u*.log )
      if (( ${#files[@]} > 0 )); then
        AVG_MS=$(grep -h "Time per request:" "${files[@]}" \
                 | awk '{sum+=$4; n++} END { if (n>0) printf "%.3f", sum/n }')

        [[ -z "$AVG_MS" ]] && FAILED=1 && AVG_MS=0
      else
        FAILED=1
      fi
    fi

    echo "${F},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
  done
done

echo "✨ Benchmark fanout terminé. Résultats dans ${CSV}"
echo "   Logs détaillés : ${LOG_DIR}"
