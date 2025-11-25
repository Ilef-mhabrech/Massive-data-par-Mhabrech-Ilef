import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
import matplotlib.patches as mpatches

###############################################################################
# Plot post.png à partir de out/post.csv (SANS ÉCART-TYPE)
###############################################################################

# Dossier racine du projet (parent de scripts/)
BASE_DIR = Path(__file__).resolve().parents[1]
csv_path = BASE_DIR / "out" / "post.csv"

# Chargement du CSV
df = pd.read_csv(csv_path)

# AVG_TIME est en ms -> on passe en secondes
df["AVG_TIME_S"] = df["AVG_TIME"] / 1000.0

# Agrégation par nombre de posts (PARAM)
params = sorted(df["PARAM"].unique())  # ex : [10, 100, 1000]

means = []
failed_flags = []

for p in params:
    subset = df[df["PARAM"] == p]
    means.append(subset["AVG_TIME_S"].mean())
    failed_flags.append(subset["FAILED"].any())

# Création de la figure
plt.figure(figsize=(8, 4))
ax = plt.gca()

x_pos = range(len(params))

bars = ax.bar(
    x_pos,
    means,
    edgecolor="black",   # plus de yerr donc plus propre
)

# Hachures si au moins une requête a échoué
for bar, failed in zip(bars, failed_flags):
    if failed:
        bar.set_hatch("//")

# Axe X
ax.set_xticks(list(x_pos))
ax.set_xticklabels([str(p) for p in params])

# Titres / labels
ax.set_title("Temps moyen par requête selon le nombre de posts (c=50)")
ax.set_xlabel("Posts par utilisateur")
ax.set_ylabel("Temps moyen par requête (s)")
ax.grid(axis="y", linestyle="--", alpha=0.3)

# --------------------------------------------------------------------
# Légende SANS écart-type
# --------------------------------------------------------------------
ok_patch = mpatches.Patch(
    facecolor=bars[0].get_facecolor(),
    edgecolor="black",
    label="Toutes les requêtes OK",
)

fail_patch = mpatches.Patch(
    facecolor=bars[0].get_facecolor(),
    edgecolor="black",
    hatch="//",
    label="Au moins une requête échouée",
)

ax.legend(handles=[ok_patch, fail_patch], loc="upper left")

plt.tight_layout()

# Sauvegarde
out_path = BASE_DIR / "out" / "post.png"
plt.savefig(out_path, dpi=150)
plt.show()

/* 
rajouter l'ecart tyoe et son clé  */ 
