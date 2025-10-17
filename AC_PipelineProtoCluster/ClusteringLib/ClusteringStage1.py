"""
Optimization first stage results clustering program

@version 1.00
"""

import pandas as pd
from sklearn.cluster import KMeans
import sqlite3
import argparse

# Configure command line arguments parser
parser = argparse.ArgumentParser(description="Сlustering passes for previous job(s)")
parser.add_argument("db_path", type=str, help="Path to database file")
parser.add_argument("id_task", type=int, help="ID of current task")
parser.add_argument("--id_parent_job", type=str, help="ID of parent job(s)")
parser.add_argument("--n_clusters", type=int, default=256, help="Number of clusters")
parser.add_argument(
    "--min_custom_ontester",
    type=float,
    default=0,
    help="Min value for `custom_ontester`",
)
parser.add_argument(
    "--min_trades", type=float, default=40, help="Min value for `trades`"
)
parser.add_argument(
    "--min_sharpe_ratio", type=float, default=0.7, help="Min value for `sharpe_ratio`"
)

# Read command line argument values to variables
args = parser.parse_args()
db_path = args.db_path
id_task = args.id_task
id_parent_job = args.id_parent_job
n_clusters = args.n_clusters
min_custom_ontester = args.min_custom_ontester
min_trades = args.min_trades
min_sharpe_ratio = args.min_sharpe_ratio

# Set connection to the database
connection = sqlite3.connect(db_path)
cursor = connection.cursor()

# Mark the task start
cursor.execute(f"""UPDATE tasks SET status='Processing' WHERE id_task={id_task};""")
connection.commit()

# Create a table for clustering results if absent
cursor.execute(
    """CREATE TABLE IF NOT EXISTS passes_clusters (
    id_task INTEGER,
    id_pass INTEGER,
    cluster INTEGER
);"""
)

# Clear the result table from previously obtained results
cursor.execute(f"""DELETE FROM passes_clusters WHERE id_task={id_task};""")

# Load data on parent job passes for the current task to dataframe
query = f"""SELECT p.*
FROM passes p
    JOIN
    tasks t ON t.id_task = p.id_task
    JOIN
    jobs j ON j.id_job = t.id_job    
WHERE p.profit > 0 AND 
      j.id_job IN ({id_parent_job}) AND
      p.custom_ontester >= {min_custom_ontester} AND
      p.trades >= {min_trades} AND 
      p.sharpe_ratio >= {min_sharpe_ratio};"""

df = pd.read_sql(query, connection)

# Display dataframe
print(df)

# List of dataframe columns
print(*enumerate(df.columns), sep="\n")

# Launch clustering on some dataframe columns
kmeans = KMeans(n_clusters=n_clusters, n_init="auto", random_state=42).fit(
    df.iloc[:, [7, 8, 9, 24, 29, 30, 31, 32, 33, 36, 45, 46]]
)

# Add cluster indices to dataframe
df["cluster"] = kmeans.labels_

# Set the current task ID
df["id_task"] = id_task

# Sort dataframe by clusters and normalized profit
df = df.sort_values(["cluster", "custom_ontester"])

# Display dataframe
print(df)

# Group strings by cluster and take by one string
# with the highest normalized profit from each cluster
df = df.groupby("cluster").agg("last").reset_index()

# Display dataframe
print(df)

# Leave only id_task, id_pass and cluster columns in dataframe
df = df.iloc[:, [2, 1, 0]]

# Display dataframe
print(df)

# Save dataframe to the passes_clusters table (replacing the existing one)
df.to_sql("passes_clusters", connection, if_exists="append", index=False)

# Mark task completion
cursor.execute(f"""UPDATE tasks SET status='Done' WHERE id_task={id_task};""")
connection.commit()

# Close connection
connection.close()
