#!/usr/bin/env bash
# Benchmark de la concurrence pour TinyInsta
# Produit out/conc.csv au format demandé :
# PARAM,AVG_TIME,RUN,FAILED

set -euo pipefail

# URL de ton appli déployée
APP_URL="https://maximal-beach-473712-d1.ew.r.appspot.com"

# Utilisateur dont on lit la timeline
USER="benchA1"

# Nombre total de requêtes par run
TOTAL_REQUESTS=500

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

# Niveaux de concurrence demandés
CONCURRENCY_LEVELS=(1 10 20 50 100 1000)

for C in "${CONCURRENCY_LEVELS[@]}"; do
  for RUN in 1 2 3; do
    echo "=== C=$C RUN=$RUN ==="

    # Nouveau chemin pour les logs
    LOG="$LOG_DIR/conc_C${C}_R${RUN}.log"

    FAILED=0
    AVG_MS=0

    # On lance ab ; si échec => FAILED=1
    if ab -n "$TOTAL_REQUESTS" -c "$C" \
      "${APP_URL}/api/timeline?user=${USER}&limit=20" >"$LOG" 2>&1; then

      # Extraction du temps moyen
      AVG_MS=$(grep "Time per request:" "$LOG" | head -n 1 | awk '{print $4}')

      if [[ -z "$AVG_MS" ]]; then
        FAILED=1
        AVG_MS=0
        echo "  -> Impossible d'extraire le temps moyen, marqué FAILED=1"
      fi
    else
      FAILED=1
      AVG_MS=0
      echo "  -> 'ab' a échoué pour C=$C RUN=$RUN. FAILED=1"
    fi

    # Ajout au CSV
    echo "${C},${AVG_MS},${RUN},${FAILED}" >> "$CSV"
  done
done

echo "Benchmark terminé."
echo "➜ Résultats CSV : $CSV"
echo "➜ Logs détaillés : $LOG_DIR/"
