# Casdoor

`casdoor` is a Go-based open-source Identity and Access Management (IAM) and Single Sign-On (SSO) platform.

---

## 1. Port Configuration

Casdoor exposes the following default network ports:
- **`8000` (HTTP Web UI / API)**: Main entry point for the administration interface and user login portals.
- **`389` (LDAP)**: Lightweight Directory Access Protocol directory service port.
- **`1812` (Radius)**: RADIUS authentication service port.

---

## 2. Data Persistence & Configurations

All uploaded files, avatar resources, and custom database attachments require volume mapping.

- **`/opt/casdoor/files`**: Local file system storage for user-uploaded resources (exposed as a Docker Volume).
- **`/opt/casdoor/conf/app.conf`** (Symlinked to `/conf/app.conf`): The core configuration file.

### Database Connection Configuration
Adjust the database connection in `app.conf` or pass them via database flags:
- `driverName`: Database type (e.g. `mysql`, `postgres`, `sqlite3`).
- `dataSourceName`: Database connection string parameters (e.g. `"user=postgres password=postgres host=localhost port=5432 sslmode=disable dbname=casdoor"`).

---

## 3. Quickstart Example

Run Casdoor using default configs:
```bash
docker run -d \
    --name svc-casdoor \
    -p 8000:8000 \
    -p 389:389 \
    -p 1812:1812 \
    -v casdoor_uploads:/opt/casdoor/files \
    labnow/casdoor:latest
```
