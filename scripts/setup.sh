#!/usr/bin/env bash
# Writes configuration only; starting containers remains the operator's choice.
set -euo pipefail
umask 077
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for bin in docker openssl; do
    command -v "$bin" >/dev/null || { echo "$bin is required." >&2; exit 1; }
done
docker compose version >/dev/null

mode=${1:-}
case "$mode" in ''|--garage) ;; *) echo 'Usage: ./scripts/setup.sh [--garage]' >&2; exit 1 ;; esac
if [ -f .env ] && [ "$mode" != --garage ]; then
    echo '.env already exists; edit it directly. Use --garage to replace only storage settings.'
    exit 0
fi
if [ "$mode" = --garage ] && [ ! -f .env ]; then
    echo 'Run setup without --garage first.' >&2
    exit 1
fi

if [ "$mode" = --garage ] && grep -q '^GARAGE_RPC_SECRET=.' .env; then
    echo 'Garage is already configured; edit storage settings directly to preserve its credentials.' >&2
    exit 1
fi

prompt() {
    local answer
    printf '%s [%s]: ' "$2" "$3" >&2
    IFS= read -r answer || { echo 'No input received.' >&2; exit 1; }
    printf -v "$1" '%s' "${answer:-$3}"
}
# Quoting prevents Compose from expanding dollar signs in operator credentials.
write_env() {
    local value=$2
    value=${value//\'/\\\'}
    printf "%s='%s'\n" "$1" "$value"
}

if [ "$mode" != --garage ]; then
    prompt BASE_URL 'API URL' 'http://localhost:3001'
    prompt FRONTEND_URL 'Site URL' 'http://localhost:3000'
    prompt COOKIE_DOMAIN 'Shared cookie domain (blank for localhost)' ''
    prompt ROBLOX_CLIENT_ID 'Roblox OAuth client ID (optional for now)' ''
    prompt ROBLOX_CLIENT_SECRET 'Roblox OAuth client secret' ''
    prompt SITE_ADMINS 'Site admin Roblox user IDs, comma separated' ''
else
    echo 'This replaces storage credentials only. Copy existing media to Garage before switching.'
fi
prompt S3_PUBLIC_URL 'Public image URL' 'http://localhost:9000'

tmp=$(mktemp .env.XXXXXX)
trap 'rm -f "$tmp"' EXIT
if [ "$mode" = --garage ]; then
    awk '!/^(GARAGE_RPC_SECRET|S3_ENDPOINT|S3_REGION|S3_BUCKET|S3_ACCESS_KEY|S3_SECRET_KEY|S3_PUBLIC_URL)=/' .env >"$tmp"
else
    {
        for name in BASE_URL FRONTEND_URL COOKIE_DOMAIN ROBLOX_CLIENT_ID ROBLOX_CLIENT_SECRET SITE_ADMINS; do
            write_env "$name" "${!name}"
        done
        write_env ENCRYPTION_KEY "$(openssl rand -base64 32)"
        write_env POSTGRES_PASSWORD "$(openssl rand -hex 24)"
        write_env BOT_SERVICE_TOKEN "$(openssl rand -hex 32)"
        printf 'TAG=latest\nDISCORD_APP_ID=\nDISCORD_CLIENT_SECRET=\nDISCORD_BOT_TOKEN=\n'
        printf 'BOT_WORKER_URL=\nBOT_WORKER_SYNC_TOKEN=\n'
        printf 'POLICIES_REPOSITORY=TrP-Labs/Policies\nPOLICIES_REF=main\n'
    } >"$tmp"
fi
{
    write_env GARAGE_RPC_SECRET "$(openssl rand -hex 32)"
    write_env S3_ACCESS_KEY "GK$(openssl rand -hex 16)"
    write_env S3_SECRET_KEY "$(openssl rand -hex 32)"
    printf 'S3_BUCKET=trptools\nS3_REGION=garage\nS3_ENDPOINT=http://garage:3900\n'
    write_env S3_PUBLIC_URL "$S3_PUBLIC_URL"
} >>"$tmp"
mv "$tmp" .env
printf '\nSaved .env. Start when ready: docker compose up -d\n'
