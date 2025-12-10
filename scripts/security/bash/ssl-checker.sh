#!/bin/bash
# =============================================================================
# @id           ssl
# @name         ssl-checker
# @displayName  SSL Certificate Checker
# @description  Check SSL certificate expiry, chain validity, and cipher suites
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         ssl,tls,certificate,security,expiry,https,cipher
# @shells       bash
# =============================================================================

set -euo pipefail

# Source interactive utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/../../lib/interactive.sh" ]] && source "$SCRIPT_DIR/../../lib/interactive.sh"

# Script metadata
SCRIPT_NAME="SSL Certificate Checker"
SCRIPT_VERSION="1.0.0"

# Default values
DOMAINS=()
INTERACTIVE=auto
RSR_YES=0
WARN_DAYS=30
CRITICAL_DAYS=7
CHECK_CHAIN=false
CHECK_CIPHERS=false
PORT=443
TIMEOUT=10
OUTPUT_FORMAT="text"
VERBOSE=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Exit codes
EXIT_OK=0
EXIT_WARNING=1
EXIT_CRITICAL=2
EXIT_ERROR=3

# Results tracking
RESULTS=()
HAS_WARNING=false
HAS_CRITICAL=false

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Check SSL certificate expiry, chain validity, and cipher security.

${YELLOW}Usage:${NC}
    $0 [OPTIONS] [DOMAIN...]

${BOLD}Options:${NC}
    -d, --domain DOMAIN    Check specific domain (can repeat)
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -f, --file FILE        Read domains from file (one per line)
    -l, --local FILE       Check local certificate file
    -p, --port PORT        Port to connect to (default: 443)
    -w, --warn DAYS        Warning threshold days (default: 30)
    -c, --critical DAYS    Critical threshold days (default: 7)
    -C, --chain            Validate certificate chain
    -S, --ciphers          Check for weak cipher suites
    -a, --all              Run all checks (chain + ciphers)
    -t, --timeout SEC      Connection timeout (default: 10)
    -o, --output FORMAT    Output format: text, json (default: text)
    -v, --verbose          Show detailed certificate info
    -h, --help             Display this help message

${BOLD}Examples:${NC}
    ${DIM}# Check single domain${NC}
    $0 example.com

    ${DIM}# Check multiple domains${NC}
    $0 -d example.com -d api.example.com

    ${DIM}# Check with all validations${NC}
    $0 -a example.com

    ${DIM}# Check domains from file${NC}
    $0 -f domains.txt

    ${DIM}# JSON output for monitoring${NC}
    $0 -o json example.com

${BOLD}Exit Codes:${NC}
    0 - All certificates valid (> warn days)
    1 - Warning (certificate expiring within warn days)
    2 - Critical (certificate expiring within critical days or expired)
    3 - Error (connection failed, invalid arguments)

EOF
    exit 0
}

log_info() { echo -e "${BLUE}▸${NC} $1"; }
log_ok() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    HAS_WARNING=true
}
log_error() { echo -e "${RED}✗${NC} $1"; }
log_critical() {
    echo -e "${RED}${BOLD}✗${NC} $1"
    HAS_CRITICAL=true
}
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -i | --interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            -y | --yes)
                RSR_YES=1
                INTERACTIVE=false
                shift
                ;;
            -d | --domain)
                DOMAINS+=("$2")
                shift 2
                ;;
            -f | --file)
                if [[ -f "$2" ]]; then
                    while IFS= read -r line || [[ -n "$line" ]]; do
                        [[ -n "$line" && ! "$line" =~ ^# ]] && DOMAINS+=("$line")
                    done < "$2"
                else
                    log_error "File not found: $2"
                    exit $EXIT_ERROR
                fi
                shift 2
                ;;
            -l | --local)
                LOCAL_CERT="$2"
                shift 2
                ;;
            -p | --port)
                PORT="$2"
                shift 2
                ;;
            -w | --warn)
                WARN_DAYS="$2"
                shift 2
                ;;
            -c | --critical)
                CRITICAL_DAYS="$2"
                shift 2
                ;;
            -C | --chain)
                CHECK_CHAIN=true
                shift
                ;;
            -S | --ciphers)
                CHECK_CIPHERS=true
                shift
                ;;
            -a | --all)
                CHECK_CHAIN=true
                CHECK_CIPHERS=true
                shift
                ;;
            -t | --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -o | --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_ERROR
                ;;
            *)
                DOMAINS+=("$1")
                shift
                ;;
        esac
    done
}

# Check if openssl is available
check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required but not installed"
        exit $EXIT_ERROR
    fi
}

# Get certificate from domain
get_certificate() {
    local domain="$1"
    local port="${2:-443}"

    timeout "$TIMEOUT" openssl s_client -connect "${domain}:${port}" \
        -servername "$domain" < /dev/null 2> /dev/null
}

# Get certificate from local file
get_local_certificate() {
    local file="$1"
    cat "$file"
}

# Parse certificate expiry date
get_expiry_date() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -enddate 2> /dev/null | cut -d= -f2
}

# Calculate days until expiry
days_until_expiry() {
    local expiry_date="$1"
    local expiry_epoch
    local now_epoch

    # Handle both GNU and BSD date
    if date --version &> /dev/null 2>&1; then
        # GNU date
        expiry_epoch=$(date -d "$expiry_date" +%s 2> /dev/null)
    else
        # BSD date (macOS)
        expiry_epoch=$(date -jf "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2> /dev/null)
    fi

    now_epoch=$(date +%s)
    echo $(((expiry_epoch - now_epoch) / 86400))
}

# Get certificate subject
get_subject() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -subject 2> /dev/null | sed 's/subject=//'
}

# Get certificate issuer
get_issuer() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -issuer 2> /dev/null | sed 's/issuer=//'
}

# Get certificate serial
get_serial() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -serial 2> /dev/null | cut -d= -f2
}

# Get key size
get_key_size() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -text 2> /dev/null | grep "Public-Key:" | grep -oE '[0-9]+'
}

# Get signature algorithm
get_signature_algorithm() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -text 2> /dev/null | grep "Signature Algorithm:" | head -1 | awk '{print $3}'
}

# Get SAN (Subject Alternative Names)
get_san() {
    local cert="$1"
    echo "$cert" | openssl x509 -noout -text 2> /dev/null \
        | grep -A1 "Subject Alternative Name:" | tail -1 \
        | sed 's/DNS://g' | tr ',' '\n' | sed 's/^ *//'
}

# Check certificate chain
check_chain() {
    local domain="$1"
    local port="${2:-443}"

    local chain_output
    chain_output=$(timeout "$TIMEOUT" openssl s_client -connect "${domain}:${port}" \
        -servername "$domain" -showcerts < /dev/null 2>&1)

    local chain_count
    chain_count=$(echo "$chain_output" | grep -c "BEGIN CERTIFICATE" || echo "0")

    local verify_result
    verify_result=$(echo "$chain_output" | grep "Verify return code:" | cut -d: -f2 | tr -d ' ')

    if [[ "$verify_result" == "0(ok)" ]]; then
        echo "valid|$chain_count"
    else
        echo "invalid|$chain_count|$verify_result"
    fi
}

# Check for weak ciphers
check_weak_ciphers() {
    local domain="$1"
    local port="${2:-443}"
    local weak_ciphers=()

    # Check for known weak ciphers
    local weak_list=("RC4" "DES" "3DES" "MD5" "NULL" "EXPORT" "ADH")

    for cipher in "${weak_list[@]}"; do
        if timeout "$TIMEOUT" openssl s_client -connect "${domain}:${port}" \
            -servername "$domain" -cipher "$cipher" < /dev/null 2>&1 \
            | grep -q "Cipher is"; then
            weak_ciphers+=("$cipher")
        fi
    done

    # Check TLS versions
    local tls_versions=""
    for ver in "ssl3" "tls1" "tls1_1" "tls1_2" "tls1_3"; do
        if timeout "$TIMEOUT" openssl s_client -connect "${domain}:${port}" \
            -servername "$domain" "-${ver}" < /dev/null 2>&1 \
            | grep -q "Cipher is"; then
            tls_versions+="$ver "
        fi
    done 2> /dev/null

    echo "${weak_ciphers[*]:-none}|${tls_versions:-unknown}"
}

# Check single domain
check_domain() {
    local domain="$1"
    local port="${2:-443}"
    local result=""

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Domain: ${CYAN}${domain}:${port}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Get certificate
    local cert
    cert=$(get_certificate "$domain" "$port")

    if [[ -z "$cert" ]]; then
        log_error "Failed to retrieve certificate from $domain:$port"
        RESULTS+=("{\"domain\":\"$domain\",\"status\":\"error\",\"message\":\"Connection failed\"}")
        return 1
    fi

    # Parse certificate info
    local expiry_date subject issuer key_size sig_algo days_left
    expiry_date=$(get_expiry_date "$cert")
    subject=$(get_subject "$cert")
    issuer=$(get_issuer "$cert")
    key_size=$(get_key_size "$cert")
    sig_algo=$(get_signature_algorithm "$cert")
    days_left=$(days_until_expiry "$expiry_date")

    # Determine status
    local status_icon status_text status_color
    if [[ $days_left -lt 0 ]]; then
        status_icon="✗"
        status_text="EXPIRED"
        status_color="$RED"
        HAS_CRITICAL=true
    elif [[ $days_left -le $CRITICAL_DAYS ]]; then
        status_icon="✗"
        status_text="CRITICAL"
        status_color="$RED"
        HAS_CRITICAL=true
    elif [[ $days_left -le $WARN_DAYS ]]; then
        status_icon="⚠"
        status_text="WARNING"
        status_color="$YELLOW"
        HAS_WARNING=true
    else
        status_icon="✓"
        status_text="OK"
        status_color="$GREEN"
    fi

    # Display results
    echo ""
    printf "  %-20s %s\n" "Subject:" "$subject"
    printf "  %-20s %s\n" "Issuer:" "$issuer"
    printf "  %-20s %s\n" "Expires:" "$expiry_date"
    printf "  %-20s ${status_color}%d days ${status_icon} ${status_text}${NC}\n" "Days Remaining:" "$days_left"
    printf "  %-20s %s\n" "Key Size:" "${key_size} bit"
    printf "  %-20s %s\n" "Signature:" "$sig_algo"

    # Check key size
    if [[ -n "$key_size" && $key_size -lt 2048 ]]; then
        log_warn "Weak key size: ${key_size} bit (should be >= 2048)"
    fi

    # Check signature algorithm
    if [[ "$sig_algo" == *"sha1"* || "$sig_algo" == *"md5"* ]]; then
        log_warn "Weak signature algorithm: $sig_algo"
    fi

    # Verbose: Show SANs
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        echo -e "  ${DIM}Subject Alternative Names:${NC}"
        get_san "$cert" | while read -r san; do
            echo -e "    ${DIM}- $san${NC}"
        done
    fi

    # Chain validation
    if [[ "$CHECK_CHAIN" == "true" ]]; then
        echo ""
        log_info "Checking certificate chain..."
        local chain_result
        chain_result=$(check_chain "$domain" "$port")
        local chain_status chain_count
        chain_status=$(echo "$chain_result" | cut -d'|' -f1)
        chain_count=$(echo "$chain_result" | cut -d'|' -f2)

        if [[ "$chain_status" == "valid" ]]; then
            log_ok "Certificate chain valid ($chain_count certificates)"
        else
            local chain_error
            chain_error=$(echo "$chain_result" | cut -d'|' -f3)
            log_error "Certificate chain invalid: $chain_error"
            HAS_WARNING=true
        fi
    fi

    # Cipher check
    if [[ "$CHECK_CIPHERS" == "true" ]]; then
        echo ""
        log_info "Checking cipher suites..."
        local cipher_result weak_ciphers tls_versions
        cipher_result=$(check_weak_ciphers "$domain" "$port")
        weak_ciphers=$(echo "$cipher_result" | cut -d'|' -f1)
        tls_versions=$(echo "$cipher_result" | cut -d'|' -f2)

        if [[ "$weak_ciphers" == "none" ]]; then
            log_ok "No weak ciphers detected"
        else
            log_warn "Weak ciphers enabled: $weak_ciphers"
        fi

        printf "  %-20s %s\n" "TLS Versions:" "$tls_versions"

        if [[ "$tls_versions" == *"ssl3"* || "$tls_versions" == *"tls1 "* || "$tls_versions" == *"tls1_1"* ]]; then
            log_warn "Deprecated TLS versions enabled (SSLv3/TLS1.0/TLS1.1)"
        fi

        if [[ "$tls_versions" == *"tls1_3"* ]]; then
            log_ok "TLS 1.3 supported"
        fi
    fi

    # Store result for JSON output
    RESULTS+=("{\"domain\":\"$domain\",\"port\":$port,\"status\":\"$status_text\",\"days_remaining\":$days_left,\"expiry\":\"$expiry_date\",\"issuer\":\"$issuer\",\"key_size\":$key_size}")
}

# Output JSON results
output_json() {
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"warn_days\": $WARN_DAYS,"
    echo "  \"critical_days\": $CRITICAL_DAYS,"
    echo "  \"results\": ["
    local first=true
    for result in "${RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    $result"
    done
    echo ""
    echo "  ]"
    echo "}"
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"
    
    echo ""
    log_info "SSL Certificate Checker - Interactive Mode"
    echo ""
    
    # Domain entry method
    local entry_method
    entry_method=$(prompt_select "How would you like to specify domains?" \
        "Enter domains manually" \
        "Load from file" \
        "Check localhost certificate")
    
    case "$entry_method" in
        "Enter domains manually")
            echo ""
            log_info "Enter domains to check (one per line, empty line to finish):"
            while true; do
                local domain
                read -r -p "  Domain: " domain
                [[ -z "$domain" ]] && break
                DOMAINS+=("$domain")
            done
            ;;
        "Load from file")
            echo ""
            local file
            file=$(prompt_input "Enter path to domains file" "domains.txt")
            if [[ -f "$file" ]]; then
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -n "$line" && ! "$line" =~ ^# ]] && DOMAINS+=("$line")
                done < "$file"
                log_ok "Loaded ${#DOMAINS[@]} domain(s) from $file"
            else
                log_error "File not found: $file"
                return 1
            fi
            ;;
        "Check localhost certificate")
            DOMAINS+=("localhost")
            ;;
    esac
    
    if [[ ${#DOMAINS[@]} -eq 0 ]]; then
        log_error "No domains specified"
        return 1
    fi
    
    echo ""
    
    # Port selection
    local port_choice
    port_choice=$(prompt_select "Which port to check?" \
        "443 (HTTPS - default)" \
        "8443 (Alt HTTPS)" \
        "Custom port")
    
    case "$port_choice" in
        "443 (HTTPS - default)") PORT=443 ;;
        "8443 (Alt HTTPS)") PORT=8443 ;;
        "Custom port")
            echo ""
            PORT=$(prompt_input "Enter port number" "443")
            ;;
    esac
    
    echo ""
    
    # Warning thresholds
    local threshold_choice
    threshold_choice=$(prompt_select "Certificate expiry warning thresholds:" \
        "Default (30 days warn, 7 days critical)" \
        "Strict (60 days warn, 14 days critical)" \
        "Relaxed (14 days warn, 3 days critical)" \
        "Custom thresholds")
    
    case "$threshold_choice" in
        "Default (30 days warn, 7 days critical)")
            WARN_DAYS=30
            CRITICAL_DAYS=7
            ;;
        "Strict (60 days warn, 14 days critical)")
            WARN_DAYS=60
            CRITICAL_DAYS=14
            ;;
        "Relaxed (14 days warn, 3 days critical)")
            WARN_DAYS=14
            CRITICAL_DAYS=3
            ;;
        "Custom thresholds")
            echo ""
            WARN_DAYS=$(prompt_input "Warning threshold (days)" "30")
            CRITICAL_DAYS=$(prompt_input "Critical threshold (days)" "7")
            ;;
    esac
    
    echo ""
    
    # Additional checks
    local checks=()
    checks=$(prompt_multiselect "Select additional checks:" \
        "Validate certificate chain" \
        "Check for weak ciphers" \
        "Verbose output")
    
    for check in $checks; do
        case "$check" in
            "Validate certificate chain") CHECK_CHAIN=true ;;
            "Check for weak ciphers") CHECK_CIPHERS=true ;;
            "Verbose output") VERBOSE=true ;;
        esac
    done
    
    # Summary
    echo ""
    log_info "Configuration summary:"
    echo -e "  ${CYAN}•${NC} Domains: ${DOMAINS[*]}"
    echo -e "  ${CYAN}•${NC} Port: $PORT"
    echo -e "  ${CYAN}•${NC} Warning: $WARN_DAYS days, Critical: $CRITICAL_DAYS days"
    [[ "$CHECK_CHAIN" == "true" ]] && echo -e "  ${CYAN}•${NC} Chain validation: enabled"
    [[ "$CHECK_CIPHERS" == "true" ]] && echo -e "  ${CYAN}•${NC} Cipher check: enabled"
    echo ""
    
    if prompt_yes_no "Start certificate check?" "y"; then
        # Continue to run the checks (fall through to main logic)
        return 0
    else
        log_info "Check cancelled"
        exit 0
    fi
}

# Main function
main() {
    local original_args=("$@")
    parse_args "$@"
    check_dependencies

    # Determine if interactive mode should be enabled
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    # Run interactive mode if enabled
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &>/dev/null && rsr_is_interactive; then
        run_interactive
    fi

    # Check if we have domains to check
    if [[ ${#DOMAINS[@]} -eq 0 && -z "${LOCAL_CERT:-}" ]]; then
        log_error "No domains specified"
        echo "Use -h for help"
        exit $EXIT_ERROR
    fi

    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
        echo ""
        echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────┐${NC}"
        echo -e "${BOLD}${BLUE}│       SSL Certificate Checker           │${NC}"
        echo -e "${BOLD}${BLUE}│             v${SCRIPT_VERSION}                       │${NC}"
        echo -e "${BOLD}${BLUE}└─────────────────────────────────────────┘${NC}"
        echo ""
        log_info "Warning threshold: ${WARN_DAYS} days"
        log_info "Critical threshold: ${CRITICAL_DAYS} days"
    fi

    # Check local certificate
    if [[ -n "${LOCAL_CERT:-}" ]]; then
        if [[ -f "$LOCAL_CERT" ]]; then
            log_info "Checking local certificate: $LOCAL_CERT"
            # TODO: Implement local cert checking
        else
            log_error "Local certificate file not found: $LOCAL_CERT"
            exit $EXIT_ERROR
        fi
    fi

    # Check domains
    for domain in "${DOMAINS[@]}"; do
        check_domain "$domain" "$PORT"
    done

    # Output JSON if requested
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        output_json
    else
        # Summary
        echo ""
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}Summary${NC}"
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  Domains checked: ${#DOMAINS[@]}"

        if [[ "$HAS_CRITICAL" == "true" ]]; then
            log_critical "CRITICAL: Some certificates are expired or expiring very soon!"
        elif [[ "$HAS_WARNING" == "true" ]]; then
            log_warn "WARNING: Some certificates are expiring soon"
        else
            log_ok "All certificates are valid"
        fi
    fi

    # Exit with appropriate code
    if [[ "$HAS_CRITICAL" == "true" ]]; then
        exit $EXIT_CRITICAL
    elif [[ "$HAS_WARNING" == "true" ]]; then
        exit $EXIT_WARNING
    else
        exit $EXIT_OK
    fi
}

main "$@"
