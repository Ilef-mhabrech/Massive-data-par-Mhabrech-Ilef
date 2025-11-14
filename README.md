# Massive-data-par-Mhabrech-Ilef

### Projet Données Massives & Cloud — Benchmark TinyInsta 
### Étudiante : Ilef Mhabrech

### 1. Application TinyInsta déployée
URL de l'application TinyInsta déployée sur Google Cloud :
 https://maximal-beach-473712-d1.ew.r.appspot.com
 
### 2. Structure du dépôt
Massive-data-par-Mhabrech-Ilef/
│
├── out/                         # Résultats finaux obligatoire pour le rendu
│   ├── conc.csv
│   ├── post.csv
│   ├── fanout.csv
│   ├── conc.png
│   ├── post.png
│   ├── fanout.png
│   ├── log_conc/
│   ├── log_post/
│   └── log_fanout/
│
├── scripts/
│   ├── bench_conc.sh            # Benchmark concurrence
│   ├── bench_post.sh            # Benchmark posts
│   ├── bench_fanout.sh          # Benchmark fanout
│   ├── plot_conc.py             # Génère conc.png
│   ├── plot_post.py             # Génère post.png
│   └── plot_fanout.py           # Génère fanout.png
│
└── README.md                    # Ce fichier




### 3. Génération des données (seed)
Le Datastore est rempli selon les paramètres du projet :
1000 utilisateurs
50 posts par utilisateur
20 followees random par utilisateur

Commande utilisée :
```sh
curl -X POST \
  -H "X-Seed-Token: change-me-seed-token" \
  "https://maximal-beach-473712-d1.ew.r.appspot.com/admin/seed?users=1000&posts=50&follows_min=20&follows_max=20&prefix=benchA"
  ```
Les données seedées sont visibles dans GCP → Datastore.

### 4.  Benchmark 1 – Passage à l’échelle sur la concurrence

** Objectif : 
Mesurer la performance de la timeline en faisant varier le nombre d’utilisateurs simulés simultanément :
1, 10, 20, 50, 100, 1000 utilisateurs concurrents . 

3 runs par valeur → produire :
conc.csv
conc.png
logs ApacheBench dans out/log_conc/

▶Exécution du benchmark Depuis la racine du projet pour génerer un fichier conc.csv:

```sh
cd scripts/ 
chmod +x bench_conc.sh
./bench_conc.sh
```

▶la commande pour génerer le graphe conc.png :

```sh
python3 plot_conc.py
```

Résultats dans :
out/conc.csv
out/conc.png
out/log_conc/*.log

### 5. Benchmark 2 – Passage à l’échelle sur la taille des données (posts)
Paramètres : 
Concurrence : 50
Followees fixes : 20
Varier le nombre de posts par user :
10, 100, 1000

▶ Lancer Depuis la racine du projetpour génerer un fichier post.csv:

```sh 
chmod +x bench_post.sh
./bench_post.sh
```

▶ Générer le graphique
```sh
python3 scripts/plot_post.py
```

Fichiers générés :
out/post.csv
out/post.png
out/log_post/*.log

### 6. Benchmark 3 – Variation du fanout (nombre de followees)

Concurrence fixe : 50
Posts fixes : 100
Followees à tester :
10, 50, 100

▶on lance cette commande pour avoir le fichier fanout.csv :

```sh
chmod +x bench_fanout.sh
./scripts/bench_fanout.sh
```

▶Générer le graphique : 

```sh
python3 scripts/plot_fanout.py
```

Fichiers générés :
out/fanout.csv
out/fanout.png
out/log_fanout/*.log

### 7. Fichiers finaux : 
Dans le dossier out/ :
Fichier	Description
conc.csv	Résultats du benchmark de concurrence
post.csv	Résultats selon le nombre de posts
fanout.csv	Résultats selon le fanout
conc.png	Graphique de concurrence
post.png	Graphique des posts
fanout.png	Graphique du fanout
log_*	Logs ApacheBench


### 9.  Interprétation rapide : 
Le temps de réponse augmente avec la concurrence (effet direct de la charge sur App Engine).
Le nombre de posts augmente légèrement la latence (plus de données à merger).
Le fanout (nombre de followees) est le facteur le plus critique :
plus il est élevé, plus la requête GQL IN devient lourde
→ car elle provoque un k-way merge côté Datastore.
Les erreurs apparaissent lorsque la charge dépasse la capacité "autoscaling minimal" d’App Engine Standard.
