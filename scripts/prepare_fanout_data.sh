#!/usr/bin/env bash
# ============================================================
# Préparation des données pour l'expérience FANOUT
# TinyInsta - Mhabrech Ilef 2025
#
# 1) Wipe complet du Datastore
# 2) Création :
#       - 1000 utilisateurs  (user1..user1000)
#       - 100 posts par utilisateur  => 100 000 posts
#       - 20 followees par utilisateur (fanout initial)
# ============================================================

set -euo pipefail

# Nombre d'utilisateurs et de posts
USERS=1000
POSTS_PER_USER=100
INITIAL_FANOUT=20          # fanout initial (tu pourras le changer ensuite)

# Racine du projet (on remonte depuis scripts/)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WIPE_SCRIPT="$ROOT_DIR/wipe_datastore.py"
SEED_SCRIPT="$ROOT_DIR/massive-gcp/seed.py"

TOTAL_POSTS=$((USERS * POSTS_PER_USER))

echo "🧹 Étape 1 : wipe complet du Datastore..."
python3 "$WIPE_SCRIPT"
echo "   ✔ Datastore vidé."
echo

echo "🌱 Étape 2 : seed initial pour FANOUT"
echo "   → USERS       = $USERS"
echo "   → POSTS       = $TOTAL_POSTS  (= $POSTS_PER_USER posts/user)"
echo "   → FOLLOWEES   = $INITIAL_FANOUT / user"
echo

python3 "$SEED_SCRIPT" \
  --users "$USERS" \
  --posts "$TOTAL_POSTS" \
  --follows-min "$INITIAL_FANOUT" \
  --follows-max "$INITIAL_FANOUT" \
  --prefix user

echo
echo "✅ Préparation terminée :"
echo "   - $USERS users"
echo "   - $TOTAL_POSTS posts"
echo "   - $INITIAL_FANOUT followees par user (fanout initial)"
echo "Tu peux maintenant lancer ton script generate_fanout.sh pour faire varier le fanout."
