import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
import matplotlib.patches as mpatches

###############################################################################
# Plot fanout.png à partir de out/fanout.csv
###############################################################################

# Dossier racine du projet (parent de scripts/)
BASE_DIR = Path(__file__).resolve().parents[1]
csv_path = BASE_DIR / "out" / "fanout.csv"

# Chargement du CSV
df = pd.read_csv(csv_path)

# AVG_TIME est en ms -> on passe en secondes
df["AVG_TIME_S"] = df["AVG_TIME"] / 1000.0

# Agrégation par nombre de followees (PARAM)
params = sorted(df["PARAM"].unique())  # [10, 50, 100]

means = []
stds = []
failed_flags = []

for p in params:
    subset = df[df["PARAM"] == p]
    means.append(subset["AVG_TIME_S"].mean())
    stds.append(subset["AVG_TIME_S"].std(ddof=0))
    failed_flags.append(subset["FAILED"].any())

# Création de la figure
plt.figure(figsize=(8, 4))
ax = plt.gca()

x_pos = range(len(params))

bars = ax.bar(
    x_pos,
    means,
    yerr=stds,
    capsize=5,
    edgecolor="black",
)

# Hachures si au moins une requête a échoué pour ce PARAM
for bar, failed in zip(bars, failed_flags):
    if failed:
        bar.set_hatch("//")

# Axe X
ax.set_xticks(list(x_pos))
ax.set_xticklabels([str(p) for p in params])

# Titres / labels
ax.set_title("Temps moyen par requête selon le nombre de followees (posts=100, c=50)")
ax.set_xlabel("Nombre de followees par utilisateur")
ax.set_ylabel("Temps moyen par requête (s)")
ax.grid(axis="y", linestyle="--", alpha=0.3)

# Légende (incluant la clé pour l'écart-type)
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

std_patch = mpatches.Patch(
    facecolor="white",
    edgecolor="black",
    label="Barres noires = écart-type",
)

ax.legend(handles=[ok_patch, fail_patch, std_patch], loc="upper left")

# Texte global sur l'ordre de grandeur de l'écart-type
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

# Sauvegarde
out_path = BASE_DIR / "out" / "fanout.png"
plt.savefig(out_path, dpi=150)
plt.show()
