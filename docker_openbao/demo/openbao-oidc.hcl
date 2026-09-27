# OpenBao server configuration for the Web UI and OIDC login.
#
# Replace the example hostname and certificate paths before starting OpenBao.
# The OIDC auth method and role are configured after startup through the CLI/API;
# they are not server configuration stanzas.

ui = true

api_addr     = "https://openbao.example.com:8200"
cluster_addr = "https://openbao.example.com:8201"

# OpenBao runs as a non-root container user. Disable mlock unless the runtime
# grants CAP_IPC_LOCK and the host is configured for mlock.
disable_mlock = true

storage "raft" {
  path    = "/openbao/data"
  node_id = "openbao-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"

  tls_disable     = false
  tls_cert_file   = "/openbao/tls/tls.crt"
  tls_key_file    = "/openbao/tls/tls.key"
}

# Optional: set this only when the OpenBao UI is served behind a reverse proxy
# and the external URL differs from api_addr.
# cluster_name = "openbao-production"
