#!/usr/bin/env bash
# ============================================================
# Benchmark fanout (fanout.csv)
# TinyInsta - Mhabrech Ilef 2025
#
# Objectif :
# - Fixer le nombre de posts par user à 100 (=> 100 000 posts pour 1000 users)
# - Faire varier le fanout (nombre de followees) : 10, 50, 100
# - Concurrence fixe : 50 utilisateurs simultanés
# - 3 runs par config
# - Résultats : out/fanout.csv
# ============================================================

set -euo pipefail
shopt -s nullglob

APP_URL="https://projectcloud-479410.ew.r.appspot.com"

MAX_USERS=1000          # nombre d'utilisateurs
POSTS_PER_USER=100      # posts par user (fixé)
FOLLOWERS_VALUES=(10 50 100)  # fanout à tester
CONCURRENCY=50          # 50 utilisateurs concurrents
RUNS=3                  # 3 répétitions

# On remonte d’un dossier pour utiliser la racine du projet
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_DIR="$OUT_DIR/log_fanout"
CSV="$OUT_DIR/fanout.csv"

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"

# Première création du CSV si inexistant
if [[ ! -f "$CSV" ]]; then
    echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"
fi

# ============================================================
# 1) Remettre les posts à 100 par user
#    => supprimer tous les Post puis reseed 100 000 posts
# ============================================================

echo "📊 Mise en place des données : 100 posts/user (100 000 posts au total)"

echo "🧹 Suppression de tous les posts 'Post' en batch…"

python3 - << 'EOF'
from google.cloud import datastore

client = datastore.Client()

def delete_batch(limit: int = 1000) -> int:
    """
    Supprime jusqu'à 'limit' entités de type Post.
    Retourne le nombre réellement supprimé.
    """
    query = client.query(kind="Post")
    query.keys_only()
    it = query.fetch(limit=limit)
    keys = [e.key for e in it]
    if not keys:
        return 0
    client.delete_multi(keys)
    return len(keys)

total_deleted = 0
batch_size = 1000

while True:
    n = delete_batch(batch_size)
    if n == 0:
        break
    total_deleted += n
    print(f"   → Supprimé {total_deleted} posts au total…")

print(f"✅ Suppression terminée. Total supprimé : {total_deleted}")
EOF

TOTAL_POSTS=$(( POSTS_PER_USER * MAX_USERS ))
echo "🌱 Seed des données : ${MAX_USERS} users, ${TOTAL_POSTS} posts (100/user)…"

python3 "${ROOT_DIR}/massive-gcp/seed.py" \
  --users "$MAX_USERS" \
  --posts "$TOTAL_POSTS" \
  --follows-min 20 \
  --follows-max 20 \
  --prefix user

echo "📊 Vérification du nombre de posts…"
python3 - << 'EOF'
from google.cloud import datastore

client = datastore.Client()
query = client.query(kind="Post")
count = sum(1 for _ in query.fetch())
print(f"   → Nombre de posts dans Datastore : {count}")
EOF

# ============================================================
# 2) Fonction utilitaire : choisir des users aléatoires
# ============================================================

pick_random_users() {
  seq 1 "$MAX_USERS" | shuf | head -n "$CONCURRENCY"
}

# ============================================================
# 3) Boucle sur les différents fanout
# ============================================================

for FANOUT in "${FOLLOWERS_VALUES[@]}"; do
  echo ""
  echo "============================================================"
  echo "🔁 FANOUT = ${FANOUT} followees/user (50 users concurrents)"
  echo "============================================================"

  # 3.1 Ajuster les relations de suivi sans toucher aux posts
  echo "🔧 Ajustement des followees (follows-min = follows-max = ${FANOUT})…"

  python3 "${ROOT_DIR}/massive-gcp/seed.py" \
    --users "$MAX_USERS" \
    --posts 0 \
    --follows-min "$FANOUT" \
    --follows-max "$FANOUT" \
    --prefix user

  # 3.2 Benchmark pour ce fanout
  echo "🚀 Benchmark fanout=${FANOUT}…"

  for RUN in $(seq 1 $RUNS); do
    echo "=== RUN ${RUN} (fanout=${FANOUT}) ==="

    LOG_PREFIX="${LOG_DIR}/F${FANOUT}_R${RUN}"
    FAILED=0
    AVG_MS=0

    mapfile -t USERS < <(pick_random_users)

    pids=()
    for U in "${USERS[@]}"; do
      USER_ID="user${U}"
      LOG_USER="${LOG_PREFIX}_u${U}.log"

      echo "   → ab pour ${USER_ID}"

      ab -n 10 -c 1 \
        "${APP_URL}/api/timeline?user=${USER_ID}&limit=20" > "${LOG_USER}" 2>&1 &

      pids+=( "$!" )
    done

    # Attendre tous les ab
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        FAILED=1   # au moins un ab a échoué
      fi
    done

    # On calcule TOUJOURS AVG_TIME, même si FAILED=1
    files=( "${LOG_PREFIX}"_u*.log )

    if (( ${#files[@]} > 0 )); then
      AVG_MS=$(grep -h "Time per request:" "${files[@]}" \
        | awk '{sum+=$4; n++} END { if (n>0) printf "%.3f", sum/n }')

      # Si grep/awk n’a rien trouvé → on garde FAILED=1 et AVG_MS=0
      if [[ -z "$AVG_MS" ]]; then
        FAILED=1
        AVG_MS=0
      fi
    else
      # Aucun log = gros problème
      FAILED=1
      AVG_MS=0
    fi

    echo "   → Résumé : FANOUT=${FANOUT}, RUN=${RUN}, AVG_MS=${AVG_MS}, FAILED=${FAILED}"
    echo "${FANOUT},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
  done
done

echo ""
echo "✨ Benchmark fanout terminé."
echo "➡ Résultats dans : ${CSV}"
echo "➡ Logs dans     : ${LOG_DIR}/"
