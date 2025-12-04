from google.cloud import datastore

client = datastore.Client()
query = client.query(kind="Post")
count = len(list(query.fetch()))
print("Total posts:", count)