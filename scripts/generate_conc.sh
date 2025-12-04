#!/usr/bin/env bash
# Benchmark TinyInsta - Concurrence
# Produit out/conc.csv : PARAM,AVG_TIME,RUN,FAILED

set -euo pipefail
shopt -s nullglob

###########################################
# CONFIG
###########################################

# 👉 URL de TON appli TinyInsta
APP_URL="https://projectcloud-479410.ew.r.appspot.com"

# Nombre total de requêtes par run (tous users confondus)
TOTAL_REQUESTS=500

# Nombre d'utilisateurs existants (seed.py : user1..user1000)
MAX_USERS=1000

# 👉 On remonte d'un dossier depuis scripts/ pour aller à la racine du repo
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_DIR="$OUT_DIR/log_conc"
CSV="$OUT_DIR/conc.csv"

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"

echo "Écriture dans $CSV"
echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"

# Niveaux de concurrence
CONCURRENCY_LEVELS=(1 10 20 50 100 1000)

###########################################
# Choisir C users distincts aléatoires (sans dépendre de shuf sous macOS)
###########################################
pick_random_users() {
  local count="$1"

  python3 - "$count" "$MAX_USERS" << 'EOF'
import random, sys
count = int(sys.argv[1])
max_users = int(sys.argv[2])

users = list(range(1, max_users + 1))
random.shuffle(users)

for u in users[:count]:
    print(u)
EOF
}

###########################################
# Boucle principale : benchmarks
###########################################
for C in "${CONCURRENCY_LEVELS[@]}"; do
  for RUN in 1 2 3; do
    echo "=== C=$C RUN=$RUN ==="

    LOG_PREFIX="$LOG_DIR/C${C}_R${RUN}"
    FAILED=0
    AVG_MS=0

    # Nombre de requêtes par utilisateur (≈ TOTAL_REQUESTS au total)
    REQ_PER_USER=$(( (TOTAL_REQUESTS + C - 1) / C ))
    (( REQ_PER_USER < 1 )) && REQ_PER_USER=1

    echo "  -> $C utilisateurs simultanés, $REQ_PER_USER requêtes chacun."

    # Tirage aléatoire de C utilisateurs distincts
    mapfile -t USERS < <(pick_random_users "$C")

    # Lancer les ab en parallèle
    pids=()
    for U in "${USERS[@]}"; do
      USER_ID="user${U}"
      LOG_USER="${LOG_PREFIX}_u${U}.log"

      echo "    ab → ${USER_ID}"

      ab -n "$REQ_PER_USER" -c 1 \
        "${APP_URL}/api/timeline?user=${USER_ID}&limit=5" \
        > "$LOG_USER" 2>&1 &

      pids+=( "$!" )
    done

    # Attendre tous les ab
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        FAILED=1
      fi
    done

    # Calcul du temps moyen
    if (( FAILED == 0 )); then
      files=( "${LOG_PREFIX}"_u*.log )
      if (( ${#files[@]} > 0 )); then
        AVG_MS=$(grep -h "Time per request:" "${files[@]}" \
          | awk '{sum+=$4; n++} END {if (n>0) printf "%.3f", sum/n}')
        [[ -z "$AVG_MS" ]] && FAILED=1 && AVG_MS=0
      else
        FAILED=1
        AVG_MS=0
      fi
    fi

    echo "${C},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
  done
done

echo "Benchmark terminé."
echo "➡ CSV généré : $CSV"
echo "➡ Logs dans : $LOG_DIR"
