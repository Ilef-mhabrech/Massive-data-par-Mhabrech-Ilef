import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
import matplotlib.patches as mpatches

# --------------------------------------------------------------------
# Chargement du fichier fanout.csv
# --------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parents[1]   # dossier Massive-data-par-Mhabrech-Ilef
csv_path = BASE_DIR / "out" / "fanout.csv"

df = pd.read_csv(csv_path)

# S'assurer que AVG_TIME est bien numérique (ms → s)
df["AVG_TIME"] = pd.to_numeric(df["AVG_TIME"], errors="coerce")
df["AVG_TIME_S"] = df["AVG_TIME"] / 1000.0

# --------------------------------------------------------------------
# Agrégation : moyenne et écart-type par PARAM (fanout = nb de followees)
# --------------------------------------------------------------------
params = sorted(df["PARAM"].unique())

means = []
stds = []
failed_flags = []

for p in params:
    subset = df[df["PARAM"] == p]
    means.append(subset["AVG_TIME_S"].mean())
    stds.append(subset["AVG_TIME_S"].std())
    # True si au moins un FAILED=1 pour ce fanout
    failed_flags.append((subset["FAILED"] == 1).any())

# --------------------------------------------------------------------
# STYLE ROSE 💗
# --------------------------------------------------------------------
plt.figure(figsize=(8, 4))
ax = plt.gca()

rose = "#ff69b4"           # rose flashy
rose_clair = "#ffb7d5"     # rose clair pastel

bars = ax.bar(
    range(len(params)),
    means,
    yerr=stds,
    capsize=6,
    color=rose_clair,
    edgecolor=rose,
    ecolor=rose,
    linewidth=1.5
)

# Ajout de hachures si au moins un RUN a FAILED=1 pour ce fanout
for bar, failed in zip(bars, failed_flags):
    if failed:
        bar.set_hatch("///")
        bar.set_edgecolor("black")

# --------------------------------------------------------------------
# Axes & titres
# --------------------------------------------------------------------
ax.set_xticks(range(len(params)))
ax.set_xticklabels([str(p) for p in params])

ax.set_title("Temps moyen selon le fanout (followees par utilisateur)", fontsize=14, color=rose)
ax.set_xlabel("Fanout (nombre de followees par utilisateur)", fontsize=12)
ax.set_ylabel("Temps moyen par requête (s)", fontsize=12)

ax.grid(axis="y", linestyle="--", alpha=0.3)

# --------------------------------------------------------------------
# Légende
# --------------------------------------------------------------------
legend_ok = mpatches.Patch(
    facecolor=rose_clair,
    edgecolor=rose,
    label="Toutes les requêtes OK"
)
legend_failed = mpatches.Patch(
    facecolor=rose_clair,
    edgecolor="black",
    hatch="///",
    label="Au moins une requête échouée"
)

ax.legend(handles=[legend_ok, legend_failed], loc="upper left")

plt.tight_layout()

# --------------------------------------------------------------------
# Sauvegarde
# --------------------------------------------------------------------
out_path = BASE_DIR / "out" / "fanout.png"
plt.savefig(out_path, dpi=150)
plt.show()

print(f"Plot fanout généré : {out_path}")
