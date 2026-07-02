# Keycloak

`keycloak` is an enterprise-grade open-source Identity and Access Management (IAM) and Single Sign-On (SSO) solution built on top of the dynamic Java JRE (JDK-17) base image.

---

## 1. Port Configuration

Keycloak runs on the following default port:
- **`8080` (HTTP)**: Serves the administrator console, client login portals, authentication endpoints, and API.

You can modify the server's listening port at container runtime by overriding Keycloak configuration arguments or variables, such as:
- `--http-port` CLI parameter.
- `KC_HTTP_PORT` environment variable.

---

## 2. Data Persistence

In a production environment, Keycloak requires an external database (PostgreSQL, MySQL, MariaDB, Oracle, or SQL Server) to persist configuration, client profiles, and user sessions.

### Environment variables configuration:
- `KC_DB`: Database vendor (e.g. `postgres`, `mysql`).
- `KC_DB_URL`: Connection string URL (e.g. `jdbc:postgresql://postgres-db:5432/keycloak`).
- `KC_DB_USERNAME` / `KC_DB_PASSWORD`: Authentication credentials.

### File storage persistence (dev mode):
If running the default H2 database (for development), mount the data folder to persist settings:
- **`/opt/keycloak/data`**: Stores local database files.

---

## 3. Quickstart Example

Run the Keycloak container in dev mode:
```bash
docker run -d \
    --name svc-keycloak \
    -p 8080:8080 \
    -e KEYCLOAK_ADMIN=admin \
    -e KEYCLOAK_ADMIN_PASSWORD=admin \
    labnow/keycloak:latest
```
