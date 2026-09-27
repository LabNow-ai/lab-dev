# Example administrator policy for the OIDC role.
# Prefer a narrower policy in production and grant sudo only where required.

path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
