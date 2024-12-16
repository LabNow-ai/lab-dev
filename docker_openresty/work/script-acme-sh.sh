#!/bin/bash
set -ex

# Function to issue certificates
issue_certificates() {
    local ACME_EMAIL=$1
    local LIST_DOMAINS=$2

    echo "ACME_EMAIL set to ${ACME_EMAIL}"
    echo "LIST_DOMAINS set to ${LIST_DOMAINS}"

    # Validate and define email address
    ACME_EMAIL=${ACME_EMAIL:-"admin@example.com"}

    if [ -z "$LIST_DOMAINS" ]; then
        echo "Please define variable LIST_DOMAINS: domain names separated by space"
        echo "example: LIST_DOMAINS=\"example.com api.example.com\""
        exit 2
    fi

    # Split LIST_DOMAINS into array
    local DOMAINS=($LIST_DOMAINS)

    # Check for wildcard domains
    for DOMAIN in "${DOMAINS[@]}"; do
        if [[ "$DOMAIN" == *"*"* ]]; then
            echo "Wildcard domains (e.g., *.example.com) are not supported by this function."
            exit 3
        fi
    done

    # Define directories and commands
    local DIR_CERT_INSTALL="/etc/nginx/ssl"
    local DIR_WEB_ROOT="/data/letsencrypt-acme-challenge"
    local PATH_ACME="/opt/acme.sh"
    local RELOAD_CMD="nginx -t && nginx -s reload"

    # Create required directories
    mkdir -pv "$DIR_CERT_INSTALL" "$DIR_WEB_ROOT"

    # Process each domain
    for DOMAIN in "${DOMAINS[@]}"; do
        echo "Applying for certificate for domain using HTTP-01 method for: ${DOMAIN}"
        "${PATH_ACME}/acme.sh" --issue --force \
            -d "${DOMAIN}" \
            --webroot "${DIR_WEB_ROOT}" \
            --server letsencrypt

        echo "Installing domain certificate to: ${DIR_CERT_INSTALL}"
        "${PATH_ACME}/acme.sh" --install-cert \
            -d "${DOMAIN}" \
            --key-file "${DIR_CERT_INSTALL}/${DOMAIN}.key" \
            --fullchain-file "${DIR_CERT_INSTALL}/${DOMAIN}.crt" \
            --reloadcmd "${RELOAD_CMD}"

        echo "Certificate successfully applied for domain: ${DOMAIN}"
    done
}

# Call the function with parameters
issue_certificates "$1" "$2"
