#!/bin/bash
# ================================================================
#  NU Tabulation Archive  -  Linux/macOS Full Setup Script
#  Supports: Ubuntu, Debian, CentOS, RHEL, Fedora, macOS
# ================================================================

set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}  NU TABULATION ARCHIVE  -  Linux/macOS Full Setup${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""
echo "Choose setup mode:"
echo "  [1] Run with Python directly (install pip dependencies)"
echo "  [2] Run with Docker          (recommended for deployment)"
echo ""
read -p "Enter 1 or 2: " CHOICE

# ════════════════════════════════════════════════════════════════════
# DETECT OS
# ════════════════════════════════════════════════════════════════════
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|linuxmint) OS="debian" ;;
            centos|rhel|rocky|almalinux) OS="rhel" ;;
            fedora) OS="fedora" ;;
            *) OS="unknown" ;;
        esac
    fi
    echo -e "${GREEN}[OK]${NC} Detected OS: $OS"
}

# ════════════════════════════════════════════════════════════════════
if [ "$CHOICE" == "1" ]; then
# ════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${CYAN}[MODE] Python direct mode${NC}"
    detect_os

    # ── Install Python 3.11 ──────────────────────────────────────
    echo ""
    echo "[1/4] Checking Python..."
    if ! command -v python3 &>/dev/null; then
        echo "[!] Python3 not found. Installing..."
        if [ "$OS" == "debian" ]; then
            sudo apt-get update -qq
            sudo apt-get install -y python3.11 python3.11-venv python3-pip \
                                    libjpeg-turbo8 libpng-dev libfreetype6-dev
        elif [ "$OS" == "rhel" ]; then
            sudo dnf install -y python3.11 python3-pip libjpeg-turbo libpng freetype
        elif [ "$OS" == "fedora" ]; then
            sudo dnf install -y python3.11 python3-pip libjpeg libpng freetype
        elif [ "$OS" == "macos" ]; then
            if ! command -v brew &>/dev/null; then
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install python@3.11 jpeg libpng freetype
        fi
    fi
    python3 --version
    echo -e "${GREEN}[OK]${NC} Python found."

    # ── Create venv ───────────────────────────────────────────────
    echo ""
    echo "[2/4] Setting up virtual environment..."
    if [ ! -f "$PROJECT_DIR/venv/bin/activate" ]; then
        python3 -m venv "$PROJECT_DIR/venv"
        echo -e "${GREEN}[OK]${NC} Virtual environment created."
    else
        echo -e "${GREEN}[OK]${NC} Virtual environment already exists."
    fi
    source "$PROJECT_DIR/venv/bin/activate"

    # ── Install pip packages ─────────────────────────────────────
    echo ""
    echo "[3/4] Installing Python dependencies..."
    pip install --upgrade pip -q
    pip install flask==3.1.3 \
                oracledb==3.4.2 \
                pillow==12.1.1 \
                werkzeug==3.1.5 \
                cryptography==46.0.5 \
                gunicorn==23.0.0
    echo ""
    echo -e "${GREEN}[OK]${NC} Installed packages:"
    pip list | grep -iE "flask|oracledb|pillow|werkzeug|cryptography|gunicorn"

    # ── Run ───────────────────────────────────────────────────────
    echo ""
    echo "[4/4] Starting Flask app..."
    mkdir -p temp_cache
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  App running at: http://localhost:5000${NC}"
    echo -e "${CYAN}  Press CTRL+C to stop${NC}"
    echo -e "${CYAN}================================================================${NC}"
    python tabulation_web.py

# ════════════════════════════════════════════════════════════════════
elif [ "$CHOICE" == "2" ]; then
# ════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${CYAN}[MODE] Docker mode${NC}"
    detect_os

    IMAGE_NAME="nu-tabulation"
    CONTAINER_NAME="nu-tabulation-app"
    HOST_PORT=5000

    # ── Install Docker ────────────────────────────────────────────
    echo ""
    echo "[1/5] Checking Docker..."
    if ! command -v docker &>/dev/null; then
        echo "[!] Docker not found. Installing..."
        if [ "$OS" == "debian" ]; then
            sudo apt-get update -qq
            sudo apt-get install -y ca-certificates curl gnupg lsb-release
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
                sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo usermod -aG docker "$USER"
            sudo systemctl enable docker
            sudo systemctl start docker
        elif [ "$OS" == "rhel" ] || [ "$OS" == "fedora" ]; then
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io
            sudo systemctl enable docker
            sudo systemctl start docker
            sudo usermod -aG docker "$USER"
        elif [ "$OS" == "macos" ]; then
            if ! command -v brew &>/dev/null; then
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install --cask docker
            open /Applications/Docker.app
            echo "[INFO] Waiting 30s for Docker to start..."
            sleep 30
        fi
        echo -e "${GREEN}[OK]${NC} Docker installed."
    fi

    # Start docker daemon if not running
    if ! docker info &>/dev/null 2>&1; then
        echo "[!] Docker daemon not running. Starting..."
        if [ "$OS" == "macos" ]; then
            open /Applications/Docker.app
            sleep 25
        else
            sudo systemctl start docker
        fi
    fi
    docker --version
    echo -e "${GREEN}[OK]${NC} Docker is ready."

    # ── Verify required files ─────────────────────────────────────
    echo ""
    echo "[2/5] Checking required files..."
    [ ! -f "Dockerfile" ]       && echo -e "${RED}[ERROR] Dockerfile not found!${NC}"       && exit 1
    [ ! -f "requirements.txt" ] && echo -e "${RED}[ERROR] requirements.txt not found!${NC}" && exit 1
    echo -e "${GREEN}[OK]${NC} Required files found."

    # ── Remove old container ──────────────────────────────────────
    echo ""
    echo "[3/5] Removing old container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm   "$CONTAINER_NAME" 2>/dev/null || true
    echo -e "${GREEN}[OK]${NC} Done."

    # ── Build ─────────────────────────────────────────────────────
    echo ""
    echo "[4/5] Building Docker image (first time: 2-5 min)..."
    docker build -t "$IMAGE_NAME" .
    echo -e "${GREEN}[OK]${NC} Image built: $IMAGE_NAME"

    # ── Run ───────────────────────────────────────────────────────
    echo ""
    echo "[5/5] Starting container..."
    mkdir -p "$PROJECT_DIR/temp_cache"
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$HOST_PORT:5000" \
        -v "$PROJECT_DIR/temp_cache:/app/temp_cache" \
        "$IMAGE_NAME"

    echo ""
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}  SUCCESS! App running at: http://localhost:$HOST_PORT${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo "  docker logs -f $CONTAINER_NAME   <- live logs"
    echo "  docker stop $CONTAINER_NAME      <- stop"
    echo "  docker restart $CONTAINER_NAME   <- restart"
    echo -e "${GREEN}================================================================${NC}"
else
    echo -e "${RED}[ERROR] Invalid choice.${NC}"
    exit 1
fi