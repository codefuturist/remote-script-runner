#!/bin/bash
# =============================================================================
# @id           netdiag
# @name         network-diagnostics
# @displayName  Network Diagnostics
# @description  Diagnose network: connectivity, DNS, latency, port checks
# @category     network
# @version      1.0.0
# @author       codefuturist
# @tags         network,diagnostics,ping,dns,trace,ports,connectivity
# @shells       bash
# =============================================================================

set -eo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2> /dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
    [[ -n "${BASH_VERSION:-}" ]] && source "$RSR_LIB_DIR/rsr-lib.sh" interactive 2> /dev/null || true
fi

# Script metadata
SCRIPT_NAME="Network Diagnostics"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
INTERACTIVE=auto
SECTIONS=()
PING_HOSTS=""
DNS_TEST=false
TRACE_HOST=""
PORT_CHECKS=()
BANDWIDTH_TEST=false
SHOW_INTERFACES=false
SHOW_PUBLIC_IP=false
MTU_HOST=""
SHOW_LISTEN=false
PING_COUNT=4
TIMEOUT=5
OUTPUT_FORMAT="text"

# Color codes (from RSR library or fallback)
RED="${RSR_COLOR_RED:-\033[0;31m}"
GREEN="${RSR_COLOR_GREEN:-\033[0;32m}"
YELLOW="${RSR_COLOR_YELLOW:-\033[1;33m}"
BLUE="${RSR_COLOR_BLUE:-\033[0;34m}"
CYAN="${RSR_COLOR_CYAN:-\033[0;36m}"
DIM="${RSR_COLOR_DIM:-\033[2m}"
BOLD="${RSR_COLOR_BOLD:-\033[1m}"
NC="${RSR_COLOR_RESET:-\033[0m}"

# Exit codes
EXIT_OK="${RSR_EXIT_SUCCESS:-0}"
EXIT_ERROR="${RSR_EXIT_ERROR:-1}"
EXIT_INVALID_ARGS="${RSR_EXIT_USAGE:-2}"
EXIT_CONNECTIVITY=3
EXIT_DNS=4
EXIT_PORT=5

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Diagnose network: connectivity, DNS, latency, and port checks.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -a, --all               Run all diagnostics
    -s, --section SECTION   Run specific section (can repeat)
    --ping HOSTS            Ping specific hosts (comma-separated)
    --dns                   Test DNS resolution
    --trace HOST            Traceroute to host
    --port HOST:PORT        Test port connectivity (can repeat)
    --ports PORTS           Test multiple ports (comma-separated)
    --bandwidth             Run bandwidth test
    --interfaces            Show network interfaces
    --public-ip             Show public IP address
    --mtu HOST              Discover MTU to host
    --listen                Show listening services
    -c, --count N           Ping count (default: 4)
    -t, --timeout SEC       Timeout in seconds (default: 5)
    --json                  Output in JSON format

${BOLD}Sections:${NC}
    connectivity    Basic internet connectivity
    dns             DNS resolution tests
    gateway         Default gateway check
    interfaces      Network interface info
    ports           Port connectivity tests
    services        Listening services
    routing         Routing table

${BOLD}Examples:${NC}
    ${DIM}# Full diagnostics${NC}
    $0 -a

    ${DIM}# Ping specific hosts${NC}
    $0 --ping google.com,cloudflare.com

    ${DIM}# Test DNS resolution${NC}
    $0 --dns

    ${DIM}# Test port connectivity${NC}
    $0 --port example.com:443

    ${DIM}# Traceroute${NC}
    $0 --trace google.com

    ${DIM}# Show interface and public IP${NC}
    $0 --interfaces --public-ip

${BOLD}Exit Codes:${NC}
    0 - All tests passed
    1 - General error
    2 - Invalid arguments
    3 - Connectivity issues detected
    4 - DNS issues detected
    5 - Port connectivity failed

EOF
    exit 0
}

log_info() { echo -e "${BLUE}▸${NC} $1"; }
log_ok() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++)) || true
}
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++)) || true
}
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ $1 ═══${NC}"
    echo ""
}

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
            -a | --all)
                SECTIONS=("connectivity" "dns" "gateway" "interfaces" "services" "routing")
                SHOW_PUBLIC_IP=true
                shift
                ;;
            -s | --section)
                SECTIONS+=("$2")
                shift 2
                ;;
            --ping)
                PING_HOSTS="$2"
                shift 2
                ;;
            --dns)
                DNS_TEST=true
                shift
                ;;
            --trace)
                TRACE_HOST="$2"
                shift 2
                ;;
            --port)
                PORT_CHECKS+=("$2")
                shift 2
                ;;
            --ports)
                IFS=',' read -ra PORT_CHECKS <<< "$2"
                shift 2
                ;;
            --bandwidth)
                BANDWIDTH_TEST=true
                shift
                ;;
            --interfaces)
                SHOW_INTERFACES=true
                shift
                ;;
            --public-ip)
                SHOW_PUBLIC_IP=true
                shift
                ;;
            --mtu)
                MTU_HOST="$2"
                shift 2
                ;;
            --listen)
                SHOW_LISTEN=true
                shift
                ;;
            -c | --count)
                PING_COUNT="$2"
                shift 2
                ;;
            -t | --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            -*)
                echo "Unknown option: $1" >&2
                exit $EXIT_INVALID_ARGS
                ;;
            *) shift ;;
        esac
    done
}

# Check basic connectivity
check_connectivity() {
    print_header "Connectivity Test"

    local targets=("8.8.8.8" "1.1.1.1" "208.67.222.222")
    local success=0

    log_info "Testing internet connectivity..."

    for target in "${targets[@]}"; do
        log_debug "Pinging $target..."
        if ping -c 1 -W "$TIMEOUT" "$target" &> /dev/null; then
            log_ok "$target reachable"
            ((success++)) || true
        else
            log_error "$target unreachable"
        fi
    done

    if [[ $success -eq 0 ]]; then
        log_error "No internet connectivity detected"
        return 1
    elif [[ $success -lt ${#targets[@]} ]]; then
        log_warn "Partial connectivity ($success/${#targets[@]} targets reachable)"
    else
        log_ok "Internet connectivity confirmed"
    fi

    return 0
}

# Test DNS resolution
check_dns() {
    print_header "DNS Resolution"

    log_info "Testing DNS resolution..."

    # Get configured nameservers
    local nameservers=()
    if [[ -f /etc/resolv.conf ]]; then
        while read -r line; do
            if [[ "$line" =~ ^nameserver ]]; then
                nameservers+=("$(echo "$line" | awk '{print $2}')")
            fi
        done < /etc/resolv.conf
    fi

    if [[ ${#nameservers[@]} -gt 0 ]]; then
        log_info "Configured nameservers: ${nameservers[*]}"
    else
        log_warn "No nameservers found in /etc/resolv.conf"
    fi

    # Test domains
    local test_domains=("google.com" "cloudflare.com" "github.com")
    local dns_ok=0

    for domain in "${test_domains[@]}"; do
        local result
        result=$(host "$domain" 2> /dev/null | head -1 || nslookup "$domain" 2> /dev/null | grep "Address" | tail -1 || echo "")

        if [[ -n "$result" && "$result" != *"not found"* && "$result" != *"NXDOMAIN"* ]]; then
            log_ok "$domain resolved"
            log_debug "$result"
            ((dns_ok++)) || true
        else
            log_error "Failed to resolve $domain"
        fi
    done

    # Test specific nameservers
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        log_info "Testing public DNS servers..."

        local public_dns=("8.8.8.8" "1.1.1.1" "9.9.9.9")
        for dns in "${public_dns[@]}"; do
            local start end elapsed
            start=$(date +%s%3N)
            if host google.com "$dns" &> /dev/null; then
                end=$(date +%s%3N)
                elapsed=$((end - start))
                log_ok "DNS $dns responded in ${elapsed}ms"
            else
                log_error "DNS $dns failed"
            fi
        done
    fi

    if [[ $dns_ok -eq 0 ]]; then
        return 1
    fi
    return 0
}

# Check gateway
check_gateway() {
    print_header "Gateway Check"

    log_info "Checking default gateway..."

    local gateway
    gateway=$(ip route 2> /dev/null | grep default | awk '{print $3}' | head -1 || route -n 2> /dev/null | grep "^0.0.0.0" | awk '{print $2}' | head -1 || true)

    if [[ -z "$gateway" ]]; then
        log_error "No default gateway configured"
        return 1
    fi

    log_info "Default gateway: $gateway"

    # Ping gateway
    if ping -c 2 -W "$TIMEOUT" "$gateway" &> /dev/null; then
        log_ok "Gateway $gateway is reachable"

        # Get latency
        local latency
        latency=$(ping -c 3 -W "$TIMEOUT" "$gateway" 2> /dev/null | tail -1 | awk -F'/' '{print $5}' || echo "?")
        log_info "Gateway latency: ${latency}ms"
    else
        log_error "Gateway $gateway is not reachable"
        return 1
    fi

    return 0
}

# Show network interfaces
show_interfaces() {
    print_header "Network Interfaces"

    log_info "Network interface details:"
    echo ""

    if command -v ip &> /dev/null; then
        ip -br addr 2> /dev/null | while read -r iface status addrs; do
            local color="$NC"
            if [[ "$status" == "UP" ]]; then
                color="$GREEN"
            elif [[ "$status" == "DOWN" ]]; then
                color="$RED"
            fi

            printf "  ${BOLD}%-15s${NC} ${color}%-8s${NC} %s\n" "$iface" "$status" "$addrs"
        done
    elif command -v ifconfig &> /dev/null; then
        ifconfig -a 2> /dev/null | grep -E "^[a-z]|inet " | while read -r line; do
            if [[ "$line" =~ ^[a-z] ]]; then
                echo -e "\n  ${BOLD}${line%%:*}${NC}"
            else
                echo "    $line"
            fi
        done
    fi

    # Show MAC addresses
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        log_info "MAC addresses:"
        ip link show 2> /dev/null | grep -E "link/ether" | awk '{print "    " $2}' || true
    fi
}

# Show listening services
show_services() {
    print_header "Listening Services"

    log_info "Services listening on ports:"
    echo ""

    if command -v ss &> /dev/null; then
        printf "  ${BOLD}%-8s %-25s %-20s${NC}\n" "PROTO" "LOCAL ADDRESS" "PROCESS"
        echo "  ─────────────────────────────────────────────────────────"

        ss -tlnp 2> /dev/null | tail -n +2 | while read -r _ _ _ local _ _ process; do
            local proto="tcp"
            local proc_name
            proc_name=$(echo "$process" | grep -oP 'users:\("\K[^"]+' || echo "-")
            printf "  %-8s %-25s %-20s\n" "$proto" "$local" "$proc_name"
        done

        ss -ulnp 2> /dev/null | tail -n +2 | while read -r _ _ _ local _ process; do
            local proto="udp"
            local proc_name
            proc_name=$(echo "$process" | grep -oP 'users:\("\K[^"]+' || echo "-")
            printf "  %-8s %-25s %-20s\n" "$proto" "$local" "$proc_name"
        done
    elif command -v netstat &> /dev/null; then
        netstat -tlnp 2> /dev/null | tail -n +3
    else
        log_warn "ss/netstat not available"
    fi
}

# Show routing table
show_routing() {
    print_header "Routing Table"

    log_info "Current routing table:"
    echo ""

    if command -v ip &> /dev/null; then
        ip route 2> /dev/null | while read -r line; do
            if [[ "$line" =~ ^default ]]; then
                echo -e "  ${GREEN}$line${NC}"
            else
                echo "  $line"
            fi
        done
    elif command -v route &> /dev/null; then
        route -n 2> /dev/null
    fi
}

# Ping specific hosts
ping_hosts() {
    [[ -z "$PING_HOSTS" ]] && return

    print_header "Ping Test"

    IFS=',' read -ra hosts <<< "$PING_HOSTS"

    for host in "${hosts[@]}"; do
        host=$(echo "$host" | xargs) # trim whitespace
        log_info "Pinging $host..."

        local result
        result=$(ping -c "$PING_COUNT" -W "$TIMEOUT" "$host" 2>&1)

        if [[ $? -eq 0 ]]; then
            local stats
            stats=$(echo "$result" | tail -1)
            local pkt_loss
            pkt_loss=$(echo "$result" | grep -oP '\d+(?=% packet loss)' || echo "?")
            local latency
            latency=$(echo "$stats" | awk -F'/' '{print $5}' || echo "?")

            if [[ "$pkt_loss" == "0" ]]; then
                log_ok "$host: ${latency}ms avg, 0% loss"
            else
                log_warn "$host: ${latency}ms avg, ${pkt_loss}% loss"
            fi

            if [[ "$VERBOSE" == "true" ]]; then
                echo "$result" | grep -E "^(PING|---|\d+ bytes|rtt)" | sed 's/^/    /'
            fi
        else
            log_error "$host: unreachable"
        fi
    done
}

# Test port connectivity
check_ports() {
    [[ ${#PORT_CHECKS[@]} -eq 0 ]] && return

    print_header "Port Connectivity"

    for check in "${PORT_CHECKS[@]}"; do
        local host port
        host=$(echo "$check" | cut -d: -f1)
        port=$(echo "$check" | cut -d: -f2)

        if [[ -z "$host" || -z "$port" ]]; then
            log_warn "Invalid format: $check (use host:port)"
            continue
        fi

        log_info "Testing $host:$port..."

        local start end elapsed
        start=$(date +%s%3N)

        if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/$host/$port" 2> /dev/null; then
            end=$(date +%s%3N)
            elapsed=$((end - start))
            log_ok "$host:$port is open (${elapsed}ms)"
        elif command -v nc &> /dev/null && nc -z -w "$TIMEOUT" "$host" "$port" 2> /dev/null; then
            end=$(date +%s%3N)
            elapsed=$((end - start))
            log_ok "$host:$port is open (${elapsed}ms)"
        else
            log_error "$host:$port is closed or filtered"
        fi
    done
}

# Traceroute
run_traceroute() {
    [[ -z "$TRACE_HOST" ]] && return

    print_header "Traceroute"

    log_info "Tracing route to $TRACE_HOST..."
    echo ""

    if command -v traceroute &> /dev/null; then
        traceroute -w "$TIMEOUT" -m 20 "$TRACE_HOST" 2>&1 | while read -r line; do
            if [[ "$line" =~ ^\s*[0-9]+ ]]; then
                if [[ "$line" =~ \*\s*\*\s*\* ]]; then
                    echo -e "  ${DIM}$line${NC}"
                else
                    echo "  $line"
                fi
            else
                echo "  $line"
            fi
        done
    elif command -v tracepath &> /dev/null; then
        tracepath "$TRACE_HOST" 2>&1
    else
        log_warn "traceroute/tracepath not installed"
    fi
}

# Get public IP
get_public_ip() {
    [[ "$SHOW_PUBLIC_IP" != "true" ]] && return

    print_header "Public IP"

    log_info "Detecting public IP address..."

    local ip=""
    local services=("https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com")

    for service in "${services[@]}"; do
        ip=$(curl -s --max-time "$TIMEOUT" "$service" 2> /dev/null || true)
        if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
        ip=""
    done

    if [[ -n "$ip" ]]; then
        log_ok "Public IP: $ip"

        # Try to get location info
        if [[ "$VERBOSE" == "true" ]]; then
            local geo
            geo=$(curl -s --max-time "$TIMEOUT" "http://ip-api.com/line/$ip?fields=country,city,isp" 2> /dev/null || true)
            if [[ -n "$geo" ]]; then
                echo -e "    ${DIM}$geo${NC}" | tr '\n' ' '
                echo ""
            fi
        fi
    else
        log_error "Could not determine public IP"
    fi
}

# MTU discovery
discover_mtu() {
    [[ -z "$MTU_HOST" ]] && return

    print_header "MTU Discovery"

    log_info "Discovering MTU to $MTU_HOST..."

    local mtu=1500
    local min=68
    local max=1500

    while [[ $min -lt $max ]]; do
        mtu=$(((min + max + 1) / 2))

        if ping -c 1 -M "do" -s $((mtu - 28)) -W "$TIMEOUT" "$MTU_HOST" &> /dev/null; then
            min=$mtu
        else
            max=$((mtu - 1))
        fi
    done

    log_ok "Path MTU to $MTU_HOST: $min bytes"
}

# Bandwidth test
test_bandwidth() {
    [[ "$BANDWIDTH_TEST" != "true" ]] && return

    print_header "Bandwidth Test"

    if ! command -v curl &> /dev/null; then
        log_warn "curl required for bandwidth test"
        return
    fi

    log_info "Testing download speed..."

    # Use a small test file
    local url="http://speedtest.tele2.net/1MB.zip"
    local start end elapsed speed

    start=$(date +%s%3N)
    if curl -s -o /dev/null --max-time 30 "$url" 2> /dev/null; then
        end=$(date +%s%3N)
        elapsed=$((end - start))
        if [[ $elapsed -gt 0 ]]; then
            speed=$((1024 * 8 * 1000 / elapsed)) # Kbps
            if [[ $speed -gt 1000 ]]; then
                log_ok "Download: ~$((speed / 1000)) Mbps"
            else
                log_ok "Download: ~${speed} Kbps"
            fi
        fi
    else
        log_warn "Bandwidth test failed"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${BOLD}═══ Summary ═══${NC}"
    echo ""

    local total=$((TESTS_PASSED + TESTS_FAILED))

    if [[ $total -gt 0 ]]; then
        printf "${GREEN}Passed:${NC} %d\n" "$TESTS_PASSED"
        printf "${RED}Failed:${NC} %d\n" "$TESTS_FAILED"
        echo ""

        if [[ $TESTS_FAILED -eq 0 ]]; then
            echo -e "${GREEN}✓ All network tests passed${NC}"
        elif [[ $TESTS_PASSED -eq 0 ]]; then
            echo -e "${RED}✗ All network tests failed${NC}"
        else
            echo -e "${YELLOW}⚠ Some network tests failed${NC}"
        fi
    fi
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"

    echo ""

    # Main action selection
    local action
    action=$(prompt_select "What would you like to diagnose?" \
        "Full network diagnostics" \
        "Connectivity check (ping)" \
        "DNS resolution test" \
        "Port connectivity test" \
        "Traceroute to host" \
        "Network interfaces info" \
        "Custom diagnostics")

    case "$action" in
        "Full network diagnostics")
            SECTIONS=("connectivity" "dns" "gateway" "interfaces" "services" "routing")
            SHOW_PUBLIC_IP=true
            ;;
        "Connectivity check (ping)")
            echo ""
            log_info "Enter hosts to ping (comma-separated):"
            PING_HOSTS=$(prompt_input "Hosts" "google.com,cloudflare.com,8.8.8.8")
            ;;
        "DNS resolution test")
            DNS_TEST=true
            ;;
        "Port connectivity test")
            echo ""
            log_info "Enter host:port combinations (one per line, empty to finish):"
            while true; do
                local hostport
                read -r -p "  Host:Port: " hostport
                [[ -z "$hostport" ]] && break
                PORT_CHECKS+=("$hostport")
            done
            ;;
        "Traceroute to host")
            echo ""
            TRACE_HOST=$(prompt_input "Enter host for traceroute" "google.com")
            ;;
        "Network interfaces info")
            SHOW_INTERFACES=true
            SHOW_PUBLIC_IP=true
            ;;
        "Custom diagnostics")
            echo ""
            local selected
            selected=$(prompt_multiselect "Select diagnostics to run:" \
                "Basic connectivity test" \
                "DNS resolution" \
                "Default gateway check" \
                "Network interfaces" \
                "Listening services" \
                "Routing table" \
                "Public IP address" \
                "Bandwidth test")

            [[ "$selected" == *"Basic connectivity"* ]] && SECTIONS+=("connectivity")
            [[ "$selected" == *"DNS resolution"* ]] && DNS_TEST=true
            [[ "$selected" == *"Default gateway"* ]] && SECTIONS+=("gateway")
            [[ "$selected" == *"Network interfaces"* ]] && SHOW_INTERFACES=true
            [[ "$selected" == *"Listening services"* ]] && SHOW_LISTEN=true
            [[ "$selected" == *"Routing table"* ]] && SECTIONS+=("routing")
            [[ "$selected" == *"Public IP"* ]] && SHOW_PUBLIC_IP=true
            [[ "$selected" == *"Bandwidth test"* ]] && BANDWIDTH_TEST=true
            ;;
    esac

    # Summary
    echo ""
    log_info "Diagnostics configuration:"
    [[ ${#SECTIONS[@]} -gt 0 ]] && echo -e "  ${CYAN}•${NC} Sections: ${SECTIONS[*]}"
    [[ -n "$PING_HOSTS" ]] && echo -e "  ${CYAN}•${NC} Ping hosts: $PING_HOSTS"
    [[ ${#PORT_CHECKS[@]} -gt 0 ]] && echo -e "  ${CYAN}•${NC} Port checks: ${PORT_CHECKS[*]}"
    [[ -n "$TRACE_HOST" ]] && echo -e "  ${CYAN}•${NC} Traceroute: $TRACE_HOST"
    [[ "$DNS_TEST" == "true" ]] && echo -e "  ${CYAN}•${NC} DNS test: enabled"
    [[ "$SHOW_INTERFACES" == "true" ]] && echo -e "  ${CYAN}•${NC} Show interfaces: enabled"
    [[ "$BANDWIDTH_TEST" == "true" ]] && echo -e "  ${CYAN}•${NC} Bandwidth test: enabled"
    echo ""

    if prompt_yes_no "Start network diagnostics?" "y"; then
        return 0
    else
        log_info "Diagnostics cancelled"
        exit 0
    fi
}

# Main function
main() {
    local original_args=("$@")
    parse_args "$@"

    # Determine if interactive mode should be enabled
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    # Run interactive mode if enabled
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &> /dev/null && rsr_is_interactive; then
        run_interactive
    fi

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    # Run sections
    for section in "${SECTIONS[@]}"; do
        case "$section" in
            connectivity) check_connectivity ;;
            dns) check_dns ;;
            gateway) check_gateway ;;
            interfaces) show_interfaces ;;
            ports) ;; # handled separately
            services) show_services ;;
            routing) show_routing ;;
            *) log_warn "Unknown section: $section" ;;
        esac
    done

    # Run individual tests
    [[ "$DNS_TEST" == "true" ]] && check_dns
    [[ "$SHOW_INTERFACES" == "true" && ! " ${SECTIONS[*]} " =~ " interfaces " ]] && show_interfaces
    [[ "$SHOW_LISTEN" == "true" ]] && show_services

    ping_hosts
    check_ports
    run_traceroute
    get_public_ip
    discover_mtu
    test_bandwidth

    print_summary

    # Determine exit code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit $EXIT_CONNECTIVITY
    fi

    exit $EXIT_OK
}

main "$@"
