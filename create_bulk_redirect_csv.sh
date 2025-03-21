#!/bin/bash
set -euo pipefail

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found" >&2
    exit 1
fi

# Check if TARGET_URL is set and ensure it has https://
if [ -z "${TARGET_URL:-}" ]; then
    echo "TARGET_URL is not set" >&2
    exit 1
fi
if [[ "$TARGET_URL" != https://* ]]; then
    TARGET_URL="https://$TARGET_URL"
fi

# Output CSV filename
output_csv="bulk_redirects.csv"
# Remove existing CSV file if any.
rm -f "$output_csv"

# For each line (domain) in the txt file, create a CSV row.
# The CSV format is:
# <SOURCE_URL>,<TARGET_URL>,<STATUS_CODE>,<PRESERVE_QUERY_STRING>,<INCLUDE_SUBDOMAINS>,<SUBPATH_MATCHING>,<PRESERVE_PATH_SUFFIX>
# Where:
#   SOURCE_URL - the domain only (e.g. bobstbenefits.net)
#   TARGET_URL - the full URL with https://
#   STATUS_CODE - 301
#   PRESERVE_QUERY_STRING - false
#   INCLUDE_SUBDOMAINS - true
#   SUBPATH_MATCHING - true
#   PRESERVE_PATH_SUFFIX - false
while IFS= read -r domain || [ -n "$domain" ]; do
    # Skip empty lines.
    if [ -z "$domain" ]; then
        continue
    fi

    # Remove any protocol from the domain so that SOURCE_URL is the domain only.
    domain_no_protocol="${domain#http://}"
    domain_no_protocol="${domain_no_protocol#https://}"

    # Write the CSV row.
    echo "${domain_no_protocol},$TARGET_URL,301,false,true,true,false" >> "$output_csv"
done < domains_for_bulk_redirect.txt

echo "CSV file created: $output_csv"