#!/bin/bash
set -euo pipefail

check_requirements() {
    local missing_tools=()
    for tool in curl jq; do
        if ! command -v "$tool" >/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        local level="$1"
        shift
        printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    if [ ! -f "redirect_domains.txt" ]; then
        log "ERROR" "domains.txt file not found"
        exit 1
    fi
}

check_requirements

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found" >&2
    exit 1
fi

log() {
    local level="$1"
    shift
    printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

# Validate API token
log "INFO" "Validating API token..."
token_check=$(curl -s https://api.cloudflare.com/client/v4/user/tokens/verify \
    -H "Authorization: Bearer $ACCOUNT_API_TOKEN")

if ! echo "$token_check" | jq -e '.success' >/dev/null; then
    log "ERROR" "Invalid API token: $(echo "$token_check" | jq -r '.errors[]?.message')"
    log "ERROR" "Please check your token permissions: Zone.Zone (Edit), Zone.DNS (Edit), Zone.Settings (Edit), Account.Account Settings (Read)"
    exit 1
fi
log "INFO" "API token validated successfully"

# Validate required environment variables
required_vars=("ACCOUNT_ID" "ACCOUNT_API_TOKEN" "REDIRECT_LIST_NAME" "TARGET_URL" "ENABLE_QUICK_SCAN")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set" >&2
        exit 1
    fi
done

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        log "ERROR" "Invalid domain name format: $domain"
        return 1
    fi
}

create_dns_record() {
    local type="$1"
    local name="$2"
    local content="$3"
    
    local response
    response=$(curl -s "https://api.cloudflare.com/client/v4/zones/$domain_id/dns_records" \
        -H "Authorization: Bearer $ACCOUNT_API_TOKEN" \
        -H 'Content-Type: application/json' \
        -d @- <<EOF
{
  "comment": "Redirection DNS Entry, for bulk rule forwarding with Cloudflare rules.",
  "content": "$content",
  "name": "$name",
  "proxied": true,
  "ttl": 3600,
  "type": "$type"
}
EOF
    )
    
    if ! echo "$response" | jq -e '.success' >/dev/null; then
        log "ERROR" "Error creating DNS record: $(echo "$response" | jq -r '.errors[]?.message')"
        return 1
    fi
}

perform_quick_scan() {
    local domain="$1"
    local domain_id="$2"

    if [ "${ENABLE_QUICK_SCAN,,}" = "true" ]; then
        log "INFO" "DNS quick scanning ${domain}"
        scan_output=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$domain_id/dns_records/scan" \
            -H "Authorization: Bearer $ACCOUNT_API_TOKEN")
        
        if ! echo "$scan_output" | jq -e '.success' >/dev/null; then
            log "ERROR" "Quick scan failed: $(echo "$scan_output" | jq -r '.errors[]?.message')"
            return 1
        fi
        
        echo "$scan_output" | jq .
        log "INFO" "Quick scan completed for ${domain}"
    else
        log "INFO" "Quick scan disabled - skipping for ${domain}"
    fi
}

# Initialize array to store domains for bulk redirect
declare -a domains_to_be_added_to_bulk_list

for domain in $(cat redirect_domains.txt); do
    log "INFO" "Processing domain: $domain"

    validate_domain "$domain"

    add_output=$(curl https://api.cloudflare.com/client/v4/zones \
      --header "Authorization: Bearer $ACCOUNT_API_TOKEN" \
      --header "Content-Type: application/json" \
      --data "{
      \"account\": {
        \"id\": \"$ACCOUNT_ID\"
      },
      \"name\": \"$domain\",
      \"type\": \"full\"
    }")

    if ! echo "$add_output" | jq -e '.success' >/dev/null; then
        log "ERROR" "Failed to add zone for domain $domain"
        continue
    fi

    echo "$add_output" | jq -r '[.result.name,.result.id,.result.name_servers[]] | @csv' >> domain_nameservers.csv
    domain_id=$(echo "$add_output" | jq -r .result.id) 
    
    # Only add to bulk list if all DNS operations succeed
    if create_dns_record "A" "@" "192.0.2.1" && \
       create_dns_record "AAAA" "@" "100::" && \
       create_dns_record "A" "www" "192.0.2.1" && \
       create_dns_record "AAAA" "www" "100::"; then
        
        perform_quick_scan "$domain" "$domain_id"
        # Add domain to array for bulk redirect
        domains_to_be_added_to_bulk_list+=("$domain")
        log "INFO" "Domain $domain successfully processed and added to bulk list queue"
    else
        log "ERROR" "Failed to create all DNS records for $domain"
    fi
    
    printf "\n\n"
done

# Save domains to file for bulk redirect processing
if [ ${#domains_to_be_added_to_bulk_list[@]} -gt 0 ]; then
    printf "%s\n" "${domains_to_be_added_to_bulk_list[@]}" > domains_for_bulk_redirect.txt
    log "INFO" "Created domains_for_bulk_redirect.txt with ${#domains_to_be_added_to_bulk_list[@]} domains"
else
    log "WARNING" "No domains were successfully processed for bulk redirect"
fi

log "INFO" "Name servers are saved in domain_nameservers.csv"