# Cloudflare Domain Migration Tools

This repository contains two Bash scripts designed to facilitate the migration of several hundred domains that are primarily redirected. Initially, I attempted to fully utilize Cloudflare’s API for a bulk update, but issues with the bulk list update led me to develop a secondary script that generates a CSV file compatible with Cloudflare's bulk redirect interface.

Due to Cloudflare’s limit of approximately 50 non-active DNS zones at a time, the process must be performed in batches. This approach also provides an opportunity to manually review domains with special configurations.

## How It Works

To redirect a domain in Cloudflare, you must:
- Proxy the DNS records.
- Create corresponding redirect rules.

Cloudflare supports bulk URL forwarding via a bulk redirect list (see [Cloudflare Bulk Redirects](https://developers.cloudflare.com/rules/url-forwarding/bulk-redirects/)). This tool automates part of the process by:
- Creating the DNS zone.
- Adding the necessary DNS records for both the root (`@`) and `www` subdomains with these values:
  - **A record:** `192.0.2.1`
  - **AAAA record:** `100::`

These records are used to facilitate the redirect rules in Cloudflare.

## Script Overview

### `add_domains_and_update-dns-multiple.sh`
- **Prerequisites:** Validates required tools and loads API credentials from a local `.env` file.
- **Domain Processing:** Reads domains from `redirect_domains.txt`, validates their format, and attempts to add each as a new zone via Cloudflare’s API.
- **DNS Records:** Creates the necessary DNS records for each domain and, if enabled, performs a quick DNS scan.
- **Logging:** Logs successfully processed domains, saves nameservers to a CSV file, and queues domains for bulk redirection, with detailed console output throughout.

### `create_bulk_redirect_csv.sh`
- **Environment Setup:** Loads variables from a `.env` file and ensures that `TARGET_URL` is correctly defined (including the `https://` prefix).
- **CSV Generation:** Reads domains from `domains_for_bulk_redirect.txt`, removes any protocol prefixes to obtain the bare domain, and formats each into a CSV row with preset redirection parameters.
- **CSV Output:** Removes any existing CSV file before generating a new one, then outputs the CSV containing columns for the source URL, target URL, HTTP status code, and additional redirection flags.

## Configuration (`.env` File)

Create a `.env` file in the repository root with the following variables:

```dotenv
ACCOUNT_ID=""             # Cloudflare account ID (find this in the Workers & Pages section or elsewhere in your Cloudflare dashboard).
ACCOUNT_API_TOKEN=""      # Cloudflare account API token. The permissions I used included bulk management options, though these might not be necessary since I could not utliize the bulk api.
TARGET_URL=               # The full target URL (including https://) to which the domains will be redirected.
ENABLE_QUICK_SCAN="false" # Set to "true" to enable Cloudflare’s quick DNS scan for creating DNS records. Use with caution, as the quick scan may miss some records. 
```

Note: Sample images showing the required API token permissions are included in the repository as apiperms1.png.

Additional Information
This tool was developed to overcome challenges encountered with Cloudflare’s API bulk update features. While a complete API-based solution proved problematic, generating a CSV file for bulk redirection provided a practical alternative that also allows for domain review and custom rule adjustments.

Feel free to modify and extend these scripts to suit your specific migration needs.

Acknowledgments
Some aspects of this project, including parts of the code and documentation, were developed with the assistance of AI tools. Domain validation regex was reviewed in the cited code projects. 
