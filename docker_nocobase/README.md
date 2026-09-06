# Nocobase

`nocobase` is an open-source, private, scalable low-code development platform, built on top of a customized Node.js and PostgreSQL Client runtime environment.

---

## 1. Port Configuration

Nocobase operates on the following default port:
- **`13000` (HTTP)**: Serves the Web interface, API end-points, and admin dashboard.

---

## 2. Data Persistence

All local files, dynamic configurations, SQLite databases, and customization scripts must be persisted.

- **`/opt/nocobase/storage`**: Main directory for data storage, files, plugins, and SQLite databases (if used).

### Startup Hooks:
You can drop custom shell scripts into `/opt/nocobase/storage/scripts/`. The entrypoint will scan and execute any `*.sh` files in this directory before booting the main app.

### External Database Configuration (Optional):
If not using SQLite, configure database connections via standard environment variables:
- `DB_DIALECT`: `postgres` or `mysql`
- `DB_HOST`: Host address of the database service
- `DB_PORT`: Database port number
- `DB_USER`: Database login user
- `DB_PASSWORD`: Database login password
- `DB_DATABASE`: Database name

---

## 3. Quickstart Example

Run Nocobase with SQLite database storage:
```bash
docker run -d \
    --name svc-nocobase \
    -p 13000:13000 \
    -v nocobase_storage:/opt/nocobase/storage \
    -e LOCALE="zh-CN" \
    labnow/nocobase:latest
```
