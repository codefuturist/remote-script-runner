#!/bin/bash
# Distribution detection utility for git-auto-sync
# Shows detected distribution information

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║           Linux Distribution Detection                         ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    echo -e "${GREEN}✓${NC} Operating System: Linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    echo -e "${GREEN}✓${NC} Operating System: macOS"
else
    OS="unknown"
    echo -e "${RED}✗${NC} Operating System: Unknown"
    exit 1
fi

if [[ "$OS" != "linux" ]]; then
    echo -e "${YELLOW}⚠${NC}  Non-Linux system detected. Distro detection skipped."
    exit 0
fi

echo ""

# Detect distribution
DISTRO="unknown"
DISTRO_FAMILY="unknown"
DISTRO_VERSION="unknown"
PACKAGE_MANAGER="unknown"
INIT_SYSTEM="unknown"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="$ID"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    DISTRO_NAME="$NAME"
    
    echo -e "${GREEN}✓${NC} Distribution: $DISTRO_NAME"
    echo -e "  ID: $DISTRO"
    echo -e "  Version: $DISTRO_VERSION"
    
    # Determine family
    case "$ID" in
        debian|ubuntu|linuxmint|pop|elementary)
            DISTRO_FAMILY="debian"
            PACKAGE_MANAGER="apt"
            ;;
        rhel|centos|fedora|rocky|alma|ol)
            DISTRO_FAMILY="rhel"
            if command -v dnf >/dev/null 2>&1; then
                PACKAGE_MANAGER="dnf"
            else
                PACKAGE_MANAGER="yum"
            fi
            ;;
        sles|opensuse*|suse)
            DISTRO_FAMILY="suse"
            PACKAGE_MANAGER="zypper"
            ;;
        arch|manjaro|endeavouros)
            DISTRO_FAMILY="arch"
            PACKAGE_MANAGER="pacman"
            ;;
        alpine)
            DISTRO_FAMILY="alpine"
            PACKAGE_MANAGER="apk"
            ;;
        gentoo)
            DISTRO_FAMILY="gentoo"
            PACKAGE_MANAGER="emerge"
            ;;
        *)
            DISTRO_FAMILY="unknown"
            ;;
    esac
elif [ -f /etc/redhat-release ]; then
    DISTRO_FAMILY="rhel"
    PACKAGE_MANAGER="yum"
    DISTRO_NAME=$(cat /etc/redhat-release)
    echo -e "${GREEN}✓${NC} Distribution: $DISTRO_NAME"
elif [ -f /etc/debian_version ]; then
    DISTRO_FAMILY="debian"
    PACKAGE_MANAGER="apt"
    DISTRO_VERSION=$(cat /etc/debian_version)
    echo -e "${GREEN}✓${NC} Distribution: Debian $DISTRO_VERSION"
else
    echo -e "${RED}✗${NC} Distribution: Unknown"
fi

echo ""
echo -e "${GREEN}✓${NC} Distribution Family: $DISTRO_FAMILY"
echo -e "${GREEN}✓${NC} Package Manager: $PACKAGE_MANAGER"

# Detect init system
echo ""
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
    SYSTEMD_VERSION=$(systemctl --version | head -1 | awk '{print $2}')
    echo -e "${GREEN}✓${NC} Init System: SystemD (version $SYSTEMD_VERSION)"
elif [ -d /etc/init.d ] && [ -f /etc/init.d/cron ]; then
    if command -v rc-service >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
        echo -e "${GREEN}✓${NC} Init System: OpenRC"
    else
        INIT_SYSTEM="sysvinit"
        echo -e "${GREEN}✓${NC} Init System: SysVinit"
    fi
else
    INIT_SYSTEM="unknown"
    echo -e "${YELLOW}⚠${NC}  Init System: Unknown"
fi

# Detect YAML parser
echo ""
echo -e "${BOLD}YAML Parser Detection:${NC}"
if command -v yq >/dev/null 2>&1; then
    YQ_VERSION=$(yq --version 2>&1 | head -1)
    echo -e "${GREEN}✓${NC} yq: $YQ_VERSION"
else
    echo -e "${YELLOW}⚠${NC}  yq: Not installed"
fi

if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import yaml" 2>/dev/null; then
        YAML_VERSION=$(python3 -c "import yaml; print(yaml.__version__)" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} python3-yaml: version $YAML_VERSION"
    else
        echo -e "${YELLOW}⚠${NC}  python3-yaml: Not installed"
    fi
else
    echo -e "${YELLOW}⚠${NC}  python3: Not installed"
fi

if command -v ruby >/dev/null 2>&1; then
    if ruby -ryaml -e 'exit 0' 2>/dev/null; then
        echo -e "${GREEN}✓${NC} ruby-yaml: Available"
    else
        echo -e "${YELLOW}⚠${NC}  ruby-yaml: Not available"
    fi
else
    echo -e "${YELLOW}⚠${NC}  ruby: Not installed"
fi

# Installation recommendations
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║           Installation Recommendations                         ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BOLD}Paths for this system:${NC}"
if [[ $EUID -eq 0 ]]; then
    echo "  Config:      /etc/git-auto-sync/config.yaml"
    if [[ "$DISTRO_FAMILY" == "rhel" ]] || [[ "$DISTRO_FAMILY" == "suse" ]]; then
        echo "  Environment: /etc/sysconfig/git-auto-sync"
    else
        echo "  Environment: /etc/default/git-auto-sync"
    fi
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        echo "  Service:     /etc/systemd/system/git-auto-sync.service"
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        echo "  Service:     /etc/init.d/git-auto-sync"
    fi
else
    echo "  Config:      ~/.config/git-auto-sync/config.yaml"
    echo "  Environment: ~/.config/git-auto-sync/environment"
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        echo "  Service:     ~/.config/systemd/user/git-auto-sync.service"
    fi
fi

echo ""
echo -e "${BOLD}Install YAML parser:${NC}"
case "$DISTRO_FAMILY" in
    debian)
        echo "  sudo apt install yq"
        echo "  # or: sudo apt install python3-yaml"
        ;;
    rhel)
        if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
            echo "  sudo dnf install yq"
            echo "  # or: sudo dnf install python3-pyyaml"
        else
            echo "  sudo yum install python3-pyyaml"
        fi
        ;;
    suse)
        echo "  sudo zypper install yq"
        echo "  # or: sudo zypper install python3-PyYAML"
        ;;
    arch)
        echo "  sudo pacman -S yq"
        echo "  # or: sudo pacman -S python-yaml"
        ;;
    alpine)
        echo "  sudo apk add yq"
        echo "  # or: sudo apk add py3-yaml"
        ;;
    *)
        echo "  Distribution-specific package manager commands not available"
        echo "  Try: sudo apt install yq  # or python3-yaml"
        ;;
esac

echo ""
echo -e "${BOLD}Install git-auto-sync:${NC}"
echo "  sudo cp git-auto-sync.sh /usr/local/bin/"
echo "  sudo chmod +x /usr/local/bin/git-auto-sync.sh"
echo "  sudo mkdir -p /etc/git-auto-sync"
echo "  sudo cp examples/config.yaml /etc/git-auto-sync/"

if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    echo "  sudo cp examples/systemd-service /etc/systemd/system/git-auto-sync.service"
    if [[ "$DISTRO_FAMILY" == "rhel" ]] || [[ "$DISTRO_FAMILY" == "suse" ]]; then
        echo "  sudo cp examples/sysconfig-git-auto-sync /etc/sysconfig/git-auto-sync"
    else
        echo "  sudo cp examples/default-git-auto-sync /etc/default/git-auto-sync"
    fi
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable --now git-auto-sync"
elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
    echo "  sudo cp examples/openrc-init /etc/init.d/git-auto-sync"
    echo "  sudo chmod +x /etc/init.d/git-auto-sync"
    echo "  sudo rc-update add git-auto-sync default"
    echo "  sudo rc-service git-auto-sync start"
fi

echo ""
