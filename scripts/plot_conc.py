import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
import matplotlib.patches as mpatches

# --------------------------------------------------------------------
# Chargement des données conc.csv
# --------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parents[1]   # dossier Massive-data-par-Mhabrech-Ilef
csv_path = BASE_DIR / "out" / "conc.csv"

df = pd.read_csv(csv_path)

# On considère que AVG_TIME est en millisecondes -> on passe en secondes
df["AVG_TIME_S"] = df["AVG_TIME"] / 1000.0

# --------------------------------------------------------------------
# Agrégation par niveau de concurrence (PARAM)
# --------------------------------------------------------------------
params = sorted(df["PARAM"].unique())

means = []
failed_flags = []

for p in params:
    subset = df[df["PARAM"] == p]
    means.append(subset["AVG_TIME_S"].mean())
    failed_flags.append(subset["FAILED"].any())    # True si au moins un run FAILED=1

# --------------------------------------------------------------------
# Création de la figure
# --------------------------------------------------------------------
plt.figure(figsize=(8, 4))
ax = plt.gca()

x_pos = range(len(params))

bars = ax.bar(
    x_pos,
    means,
    edgecolor="black",
)

# Hachures pour les configurations où au moins une requête a échoué
for bar, failed in zip(bars, failed_flags):
    if failed:
        bar.set_hatch("//")

# Axe X
ax.set_xticks(list(x_pos))
ax.set_xticklabels([str(p) for p in params])

# Titres
ax.set_title("Temps moyen par requête selon la concurrence")
ax.set_xlabel("Nombre d'utilisateurs concurrents")
ax.set_ylabel("Temps moyen par requête (s)")

ax.grid(axis="y", linestyle="--", alpha=0.3)

# --------------------------------------------------------------------
# Légende (sans écart-type)
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

ax.legend(
    handles=[ok_patch, fail_patch],
    loc="upper left",
)

plt.tight_layout()

# --------------------------------------------------------------------
# Sauvegarde de l'image
# --------------------------------------------------------------------
out_path = BASE_DIR / "out" / "conc.png"
plt.savefig(out_path, dpi=150)
plt.show()
