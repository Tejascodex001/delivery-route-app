import sqlite3
conn = sqlite3.connect('/home/tejas/Projects/Delivery_route_optimize/delivery-route-app/backend/routes.db')
cursor = conn.cursor()
create_table_sql = """
CREATE TABLE IF NOT EXISTS completed_routes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    ors_duration_minutes REAL NOT NULL,
    total_distance_km REAL NOT NULL,
    num_stops INTEGER NOT NULL,
    actual_duration_minutes REAL NOT NULL
);"""
cursor.execute(create_table_sql)
conn.commit()
conn.close()
print("Database 'routes.db' and table 'completed_routes' created successfully.")