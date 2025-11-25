#!/usr/bin/env bash
# Seed des jeux de données pour l'expérience post (10, 100, 1000 posts/user)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEED_PY="$ROOT_DIR/massive-gcp/seed.py"

USERS=1000
FOLLOWS_MIN=20
FOLLOWS_MAX=20

echo "=== Seed pour 10 posts par utilisateur ==="
python3 "$SEED_PY" \
  --users "$USERS" \
  --posts $((USERS * 10)) \
  --follows-min "$FOLLOWS_MIN" \
  --follows-max "$FOLLOWS_MAX" \
  --prefix "posts10_"
//il faut exactement 10 dans la base de données pas 110 
echo "=== Seed pour 100 posts par utilisateur ==="
python3 "$SEED_PY" \
  --users "$USERS" \
  --posts $((USERS * 100)) \
  --follows-min "$FOLLOWS_MIN" \
  --follows-max "$FOLLOWS_MAX" \
  --prefix "posts100_"

echo "=== Seed pour 1000 posts par utilisateur ==="
python3 "$SEED_PY" \
  --users "$USERS" \
  --posts $((USERS * 1000)) \
  --follows-min "$FOLLOWS_MIN" \
  --follows-max "$FOLLOWS_MAX" \
  --prefix "posts1000_"

echo "Seed terminé pour les 3 jeux de données (10, 100, 1000 posts/user)."
