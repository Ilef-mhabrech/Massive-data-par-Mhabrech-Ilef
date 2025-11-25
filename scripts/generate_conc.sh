#!/usr/bin/env bash
# Benchmark de la concurrence pour TinyInsta
# Produit out/conc.csv au format demandé :
# PARAM,AVG_TIME,RUN,FAILED

set -euo pipefail
shopt -s nullglob

##############################################
# CONFIGURATION
##############################################

# URL de ton appli déployée
APP_URL="https://maximal-beach-473712-d1.ew.r.appspot.com"

# Nombre total de requêtes "cible" par run (en tout, tous users confondus)
TOTAL_REQUESTS=500

# Nombre maximal d'utilisateurs dans la base (seed.py : 1000 users -> user1..user1000)
MAX_USERS=1000

# Répertoires
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/out"
LOG_DIR="$OUT_DIR/log_conc"

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"

# Fichier CSV de sortie
CSV="$OUT_DIR/conc.csv"

echo "Écriture dans $CSV"
echo "PARAM,AVG_TIME,RUN,FAILED" > "$CSV"

##############################################
# Niveaux de concurrence (= nb d'utilisateurs distincts simultanés)
##############################################

CONCURRENCY_LEVELS=(1 10 20 50 100 1000)

##############################################
# Fonction utilitaire : choisir C users distincts aléatoires
##############################################
pick_random_users() {
  local count="$1"
  # On mélange 1..MAX_USERS et on en prend "count"
  seq 1 "$MAX_USERS" | shuf | head -n "$count"
}

##############################################
# Exécution des benchmarks
##############################################

for C in "${CONCURRENCY_LEVELS[@]}"; do
  for RUN in 1 2 3; do
    echo "=== C=$C RUN=$RUN ==="

    LOG_PREFIX="$LOG_DIR/conc_C${C}_R${RUN}"
    FAILED=0
    AVG_MS=0

    # Nombre de requêtes par utilisateur (on répartit TOTAL_REQUESTS)
    # ceil(TOTAL_REQUESTS / C)
    REQ_PER_USER=$(( (TOTAL_REQUESTS + C - 1) / C ))
    if (( REQ_PER_USER < 1 )); then
      REQ_PER_USER=1
    fi

    echo "  -> $C utilisateurs distincts simultanés, $REQ_PER_USER requêtes par utilisateur."

    # Choisir C utilisateurs distincts aléatoires
    mapfile -t USERS < <(pick_random_users "$C")

    # Lancer un ab PAR UTILISATEUR en parallèle (-c 1 pour chaque, la concurrence vient du parallélisme)
    pids=()
    for U in "${USERS[@]}"; do
      USER_ID="user${U}"
      LOG_USER="${LOG_PREFIX}_u${U}.log"

      echo "    Lancement ab pour ${USER_ID} (log: $(basename "$LOG_USER"))"

      ab -n "$REQ_PER_USER" -c 1 \
        "${APP_URL}/timeline?user=${USER_ID}" >"$LOG_USER" 2>&1 &

      pids+=( "$!" )
    done

    # Attendre que tous les ab se terminent
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        FAILED=1
      fi
    done

    # Si tout s'est bien passé, on calcule la moyenne des "Time per request"
    if (( FAILED == 0 )); then
      files=( "${LOG_PREFIX}"_u*.log )

      if (( ${#files[@]} == 0 )); then
        echo "  -> Aucun log trouvé pour C=$C RUN=$RUN, FAILED=1"
        FAILED=1
        AVG_MS=0
      else
        # On récupère les "Time per request" de chaque ab et on fait la moyenne
        AVG_MS=$(grep -h "Time per request:" "${files[@]}" \
          | awk '{sum+=$4; n++} END { if (n>0) printf "%.3f", sum/n }')

        if [[ -z "${AVG_MS}" ]]; then
          echo "  -> Impossible d'extraire le temps moyen, FAILED=1"
          FAILED=1
          AVG_MS=0
        fi
      fi
    else
      echo "  -> Au moins un ab a échoué pour C=$C RUN=$RUN, FAILED=1"
      AVG_MS=0
    fi

    echo "${C},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
  done
done

##############################################
echo "Benchmark terminé."
echo "➡ CSV généré : $CSV"
echo "➡ Logs disponibles dans : $LOG_DIR/"
