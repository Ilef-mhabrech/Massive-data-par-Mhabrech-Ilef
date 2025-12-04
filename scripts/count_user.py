from google.cloud import datastore

def count_users():
    client = datastore.Client()

    query = client.query(kind="User")
    users = list(query.fetch())

    print(f"[Count] Nombre d'utilisateurs : {len(users)}")

if __name__ == "__main__":
    count_users()