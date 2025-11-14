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
params = sorted(df["PARAM"].unique())  # ex : [1, 10, 20, 50, 100, 1000]

means = []
stds = []
failed_flags = []

for p in params:
    subset = df[df["PARAM"] == p]
    means.append(subset["AVG_TIME_S"].mean())
    stds.append(subset["AVG_TIME_S"].std(ddof=0))  # écart-type (population)
    failed_flags.append(subset["FAILED"].any())    # True si au moins un run a FAILED=1

# --------------------------------------------------------------------
# Création de la figure
# --------------------------------------------------------------------
plt.figure(figsize=(8, 4))  # taille similaire à ton exemple
ax = plt.gca()

x_pos = range(len(params))

bars = ax.bar(
    x_pos,
    means,
    yerr=stds,
    capsize=5,
    edgecolor="black",
)

# Hachures pour les configurations où au moins une requête a échoué
for bar, failed in zip(bars, failed_flags):
    if failed:
        bar.set_hatch("//")

# Axe X avec les valeurs de concurrence
ax.set_xticks(list(x_pos))
ax.set_xticklabels([str(p) for p in params])

# Titres et labels
ax.set_title("Temps moyen par requête selon la concurrence")
ax.set_xlabel("Nombre d'utilisateurs concurrents")
ax.set_ylabel("Temps moyen par requête (s)")

ax.grid(axis="y", linestyle="--", alpha=0.3)

# --------------------------------------------------------------------
# Légende avec explication de l'écart-type
# --------------------------------------------------------------------
# Patch pour "toutes les requêtes OK"
ok_patch = mpatches.Patch(
    facecolor=bars[0].get_facecolor(),
    edgecolor="black",
    label="Toutes les requêtes OK",
)

# Patch pour "au moins une requête échouée"
fail_patch = mpatches.Patch(
    facecolor=bars[0].get_facecolor(),
    edgecolor="black",
    hatch="//",
    label="Au moins une requête échouée",
)

# Patch "barres noires = écart-type"
std_patch = mpatches.Patch(
    facecolor="white",
    edgecolor="black",
    label="Barres noires = écart-type",
)

ax.legend(
    handles=[ok_patch, fail_patch, std_patch],
    loc="upper left",
)

# --------------------------------------------------------------------
# Texte global indiquant l'ordre de grandeur de l'écart-type
# --------------------------------------------------------------------
global_std = df["AVG_TIME_S"].std(ddof=0)
ax.text(
    0.99,
    0.98,
    f"±{global_std:.2f}s",
    transform=ax.transAxes,
    ha="right",
    va="top",
)

plt.tight_layout()

# --------------------------------------------------------------------
# Sauvegarde de l'image dans out/conc.png
# --------------------------------------------------------------------
out_path = BASE_DIR / "out" / "conc.png"
plt.savefig(out_path, dpi=150)
plt.show()
