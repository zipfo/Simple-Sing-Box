#!/bin/bash

# blacklist-update — обновление nftables sets из C24Be/AS_Network_List
# Запускается по cron (ежедневно) или вручную

BLACKLIST_URL="https://raw.githubusercontent.com/C24Be/AS_Network_List/main/blacklists"
LOG_FILE="/var/log/blacklist-update.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

update_set() {
    local set_name=$1
    local url=$2
    local tmp_file="/tmp/blacklist-${set_name}.txt"

    if ! curl -fsSL --connect-timeout 30 --max-time 120 "$url" -o "$tmp_file"; then
        log "ERROR: failed to download $url"
        return 1
    fi

    # Skip if file is empty
    [[ ! -s "$tmp_file" ]] && { log "WARNING: empty file for $set_name"; rm -f "$tmp_file"; return 1; }

    local count
    count=$(grep -c '.' "$tmp_file")

    # Flush set and reload
    nft flush set inet filter "$set_name" 2>/dev/null || { log "ERROR: set $set_name not found"; rm -f "$tmp_file"; return 1; }

    # Build nft command file for atomic update
    {
        echo "add element inet filter $set_name {"
        paste -sd, "$tmp_file"
        echo "}"
    } > /tmp/blackload-${set_name}.nft

    if nft -f /tmp/blackload-${set_name}.nft; then
        log "OK: $set_name updated ($count entries)"
    else
        log "ERROR: failed to load $set_name"
    fi

    rm -f "$tmp_file" /tmp/blackload-${set_name}.nft
    return 0
}

# Verify nftables table exists
if ! nft list table inet filter &>/dev/null; then
    log "ERROR: nftables table inet filter not found — is nftables configured?"
    exit 1
fi

log "--- Starting blacklist update ---"

errors=0

# Government detection networks
update_set "blacklist_v4" "${BLACKLIST_URL}/blacklist-v4.txt" || ((errors++))
update_set "blacklist_v6" "${BLACKLIST_URL}/blacklist-v6.txt" || ((errors++))

log "--- Update complete (errors: $errors) ---"

exit $errors
