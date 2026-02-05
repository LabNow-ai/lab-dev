#!/bin/bash
set -ex

##########################
# Top-level global variables
##########################
ACME_SH_PATH="/opt/acme.sh"
DIR_CERT_INSTALL="/etc/nginx/ssl"
DIR_WEB_ROOT="/data/letsencrypt-acme-challenge"
RELOAD_CMD="nginx -t && nginx -s reload"
DEFAULT_ACME_EMAIL="admin@example.com"

##########################
# DNS provider environment variables template (https://github.com/acmesh-official/acme.sh/wiki/dnsapi)
# Export before running:
# Cloudflare: export CF_Key="xxx"; export CF_Email="xxx"
# DNSPod: export DP_Id="xxx"; export DP_Key="xxx"
# AWS Route53: export AWS_ACCESS_KEY_ID="xxx"; export AWS_SECRET_ACCESS_KEY="xxx"
##########################

##########################
# HTTP-01 certificate issuance
# Parameters: email, domains
##########################
issue_cert_http01() {
  local email=$1
  local domains=$2

  mkdir -pv "$DIR_CERT_INSTALL" "$DIR_WEB_ROOT"

  for d in $domains; do
    if [[ $d == *"*"* ]]; then
      echo "Wildcard detected, HTTP-01 cannot be used for $d"
      exit 3
    fi

    echo "Issuing certificate via HTTP-01 for $d"
    "$ACME_SH_PATH/acme.sh" --issue --force \
      --webroot "$DIR_WEB_ROOT" \
      -d "$d" \
      --server letsencrypt

    echo "Installing certificate for $d"
    "$ACME_SH_PATH/acme.sh" --install-cert -d "$d" \
      --key-file "$DIR_CERT_INSTALL/$d.key" \
      --fullchain-file "$DIR_CERT_INSTALL/$d.crt" \
      --reloadcmd "$RELOAD_CMD"
  done
}

##########################
# DNS-01 certificate issuance (single certificate for multiple domains)
# Parameters: email, domains, provider
##########################
issue_cert_dns01() {
  local email=$1
  local domains=$2
  local provider=$3

  if [[ -z "$provider" ]]; then
    echo "DNS provider is required for DNS-01 method"
    exit 2
  fi

  mkdir -pv "$DIR_CERT_INSTALL"

  # Split domains into array and build -d arguments
  local D_ARGS=""
  for d in $domains; do
    D_ARGS="$D_ARGS -d $d"
  done

  # Issue certificate once for all domains
  echo "Issuing certificate via DNS-01 for domains: $domains using provider $provider"
  "$ACME_SH_PATH/acme.sh" --issue --force \
    --dns "$provider" $D_ARGS \
    --server letsencrypt

  # Install certificate once (all domains together)
  local FIRST_DOMAIN=$(echo $domains | awk '{print $1}')
  "$ACME_SH_PATH/acme.sh" --install-cert -d $FIRST_DOMAIN \
    --key-file "$DIR_CERT_INSTALL/${FIRST_DOMAIN}_multi.key" \
    --fullchain-file "$DIR_CERT_INSTALL/${FIRST_DOMAIN}_multi.crt" \
    --reloadcmd "$RELOAD_CMD"

  echo "Certificate installed for all domains in one file: ${FIRST_DOMAIN}_multi.crt"
}

##########################
# Auto-detect method based on domain wildcard
# Parameters: email, domains, provider
##########################
auto_issue_cert() {
  local email=$1
  local domains=$2
  local provider=$3
  local use_dns01=false

  for d in $domains; do
    if [[ $d == *"*"* ]]; then
      use_dns01=true
      break
    fi
  done

  if $use_dns01; then
    echo "Wildcard domain detected, using DNS-01 method"
    issue_cert_dns01 "$email" "$domains" "$provider"
  else
    echo "No wildcard detected, using HTTP-01 method"
    issue_cert_http01 "$email" "$domains"
  fi
}

##########################
# Main
# Usage:
# ./script-acme-sh.sh "admin@example.com" "example.com www.example.com" [dns_provider_for_dns01]
##########################
EMAIL=${1:-$DEFAULT_ACME_EMAIL}
DOMAINS=$2
DNS_PROVIDER=$3

if [[ -z "$DOMAINS" ]]; then
  echo "Please specify domain names separated by space"
  exit 1
fi

auto_issue_cert "$EMAIL" "$DOMAINS" "$DNS_PROVIDER"
