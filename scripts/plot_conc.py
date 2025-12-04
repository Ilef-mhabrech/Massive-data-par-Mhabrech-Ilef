import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
import matplotlib.patches as mpatches

# --------------------------------------------------------------------
# Chargement des données conc.csv
# --------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parents[1]
csv_path = BASE_DIR / "out" / "conc.csv"

df = pd.read_csv(csv_path)

# Conversion ms → s
df["AVG_TIME_S"] = df["AVG_TIME"] / 1000.0

# --------------------------------------------------------------------
# Agrégation moyenne + écart-type
# --------------------------------------------------------------------
params = sorted(df["PARAM"].unique())

means = []
stds = []
failed_flags = []

for p in params:
    subset = df[df["PARAM"] == p]
    means.append(subset["AVG_TIME_S"].mean())
    stds.append(subset["AVG_TIME_S"].std())
    failed_flags.append(subset["FAILED"].any())

# --------------------------------------------------------------------
# STYLE ROSE 🌸
# --------------------------------------------------------------------
plt.figure(figsize=(9, 5))
ax = plt.gca()

# Fond rose pastel
ax.set_facecolor("#ffeef7")
plt.gcf().patch.set_facecolor("#ffeef7")

# Couleurs rose clair
bar_color = "#ff7eb9"        # rose vif
error_color = "#d94a91"      # rose foncé
edge_color = "black"

x_pos = range(len(params))

bars = ax.bar(
    x_pos,
    means,
    yerr=stds,
    capsize=6,
    color=bar_color,
    edgecolor=edge_color,
    ecolor=error_color,
    linewidth=1.2
)

# Hachures pour FAILED
for bar, failed in zip(bars, failed_flags):
    if failed:
        bar.set_hatch("//")
        bar.set_edgecolor("black")

# Axes
ax.set_xticks(list(x_pos))
ax.set_xticklabels([str(p) for p in params], fontsize=11)

# Titres & labels en rose foncé
ax.set_title("🌸 Temps moyen par requête selon la concurrence 🌸",
             fontsize=15, color="#d94a91", fontweight="bold")
ax.set_xlabel("Nombre d'utilisateurs concurrents", fontsize=12, color="#c71585")
ax.set_ylabel("Temps moyen par requête (s)", fontsize=12, color="#c71585")

# Grille
ax.grid(axis="y", linestyle="--", alpha=0.3, color="#c71585")

# --------------------------------------------------------------------
# Légende esthétique
# --------------------------------------------------------------------
ok_patch = mpatches.Patch(
    facecolor=bar_color,
    edgecolor=edge_color,
    label="Toutes les requêtes OK"
)

fail_patch = mpatches.Patch(
    facecolor=bar_color,
    edgecolor=edge_color,
    hatch="//",
    label="Au moins une requête échouée"
)

ax.legend(handles=[ok_patch, fail_patch],
          loc="upper left",
          facecolor="#ffeef7",
          edgecolor="#d94a91")

plt.tight_layout()

# --------------------------------------------------------------------
# Sauvegarde
# --------------------------------------------------------------------
out_path = BASE_DIR / "out" / "conc.png"
plt.savefig(out_path, dpi=150)
plt.show()
