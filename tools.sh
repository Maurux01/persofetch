#!/bin/bash

# Terminal Utils Installer
# Installs tools from GitHub Stars list + ASCII terminal utilities
# Supports Debian/Ubuntu and Arch Linux

set -u
# NOTA: no usamos `set -e` a propósito: alguna herramienta puede faltar en
# repos y un fallo puntual no debe abortar toda la instalación.
# POLÍTICA: todo se instala SOLO desde repos (apt en Debian, pacman en Arch).
# Nada compilado: sin cargo/rustup, sin make, sin git-clone de herramientas
# (excepción: TPM, que solo existe vía git clone y no compila nada).

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect OS
detect_os() {
    if [ -f /etc/debian_version ]; then
        OS="debian"
        log_info "Debian/Ubuntu based system detected"
    elif [ -f /etc/arch-release ]; then
        OS="arch"
        log_info "Arch Linux based system detected"
    else
        log_error "Unsupported OS. This script supports Debian and Arch Linux only."
        exit 1
    fi
}

# Update package manager
update_packages() {
    log_info "Updating package manager..."
    if [ "$OS" = "debian" ]; then
        # `apt update` no acepta -y en todas las versiones -> sin flag
        sudo apt update || log_warn "apt update falló, sigo igual."
    elif [ "$OS" = "arch" ]; then
        sudo pacman -Sy --noconfirm || log_warn "pacman -Sy falló, sigo igual."
    fi
}

# Install core tools from the list
install_core_tools() {
    log_info "Installing core terminal utilities..."
    
    if [ "$OS" = "debian" ]; then
        sudo apt install -y \
            git \
            curl \
            fzf \
            starship \
            lf \
            timg \
            tmux \
            mpd \
            playerctl \
            p7zip-full \
            gh \
            hstr \
            cmatrix \
            python3-rich \
            figlet \
            lolcat \
            bash-completion \
            chafa \
            ffmpeg \
        || log_warn "Algún paquete core falló (ver arriba). Sigo con el resto."
        
        log_warn "spotify-player, rmpc y termusic no están en repos Debian, se omiten (sin compilar)."
        
    elif [ "$OS" = "arch" ]; then
        sudo pacman -S --noconfirm \
            fzf \
            starship \
            yazi \
            timg \
            tmux \
            mpd \
            playerctl \
            p7zip \
            github-cli \
            hstr \
            cmatrix \
            python-rich \
            figlet \
            lolcat \
            bash-completion \
            chafa \
            ffmpeg \
        || log_warn "Algún paquete core falló, sigo igual."
    fi
}

# Install ASCII terminal utilities
install_ascii_tools() {
    log_info "Installing ASCII terminal utilities..."
    
    if [ "$OS" = "debian" ]; then
        # asciiquarium NO existe en repos Debian -> se omite.
        # OJO: en Debian el paquete se llama pipes-sh (con guion).
        # cbonsai y pipes-sh SÍ están en repos trixie -> solo apt, nada compilado.
        sudo apt install -y \
            cmatrix \
            figlet \
            toilet \
            lolcat \
            pipes-sh \
            cbonsai \
        || log_warn "Algún paquete ASCII falló, sigo igual."
        log_warn "asciiquarium no está en repos Debian, se omite."
        
    elif [ "$OS" = "arch" ]; then
        sudo pacman -S --noconfirm \
            cmatrix \
            figlet \
            toilet \
            lolcat \
            asciiquarium \
            pipes.sh \
            cbonsai \
        || log_warn "Algún paquete ASCII falló, sigo igual."
    fi
}

# Install music players — SOLO desde repos, nada compilado.
# Debian: spotify-player/rmpc/termusic no existen en apt -> se omiten.
# Arch: los tres están en [extra] -> pacman.
install_music_players() {
    if [ "$OS" = "debian" ]; then
        log_warn "spotify-player, rmpc y termusic no están en repos Debian, se omiten (nada compilado)."
        return 0
    elif [ "$OS" = "arch" ]; then
        log_info "Installing music players from repos (pacman)..."
        sudo pacman -S --noconfirm spotify-player rmpc termusic \
            || log_warn "Algún reproductor falló, sigo igual."
    fi
}

# Install kew — SOLO desde repos, nada compilado.
# (kew SÍ está en Debian trixie y en Arch [extra].)
install_kew() {
    if command -v kew &> /dev/null; then
        log_info "kew ya instalado, salto."
        return 0
    fi
    log_info "Installing kew from repos..."
    if [ "$OS" = "debian" ]; then
        sudo apt install -y kew \
            && log_success "kew installed" \
            || log_warn "kew falló, se omite."
    elif [ "$OS" = "arch" ]; then
        sudo pacman -S --noconfirm kew \
            && log_success "kew installed" \
            || log_warn "kew falló, se omite."
    fi
}

# Install Tmux Plugin Manager
# Excepción a la política de repos: TPM solo existe vía git clone.
# No compila nada, solo clona plugins de tmux a ~/.tmux/plugins/tpm.
install_tpm() {
    log_info "Installing Tmux Plugin Manager (TPM)..."

    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
            && log_success "TPM installed at ~/.tmux/plugins/tpm" \
            || log_warn "No se pudo clonar TPM, se omite."
    else
        log_info "TPM already installed"
    fi
}

# Install fastfetch if not present
install_fastfetch() {
    if ! command -v fastfetch &> /dev/null; then
        log_info "Installing fastfetch..."
        if [ "$OS" = "debian" ]; then
            sudo apt install -y fastfetch \
                && log_success "fastfetch installed" \
                || log_warn "fastfetch falló, se omite."
        elif [ "$OS" = "arch" ]; then
            sudo pacman -S --noconfirm fastfetch \
                && log_success "fastfetch installed" \
                || log_warn "fastfetch falló, se omite."
        fi
    else
        log_info "fastfetch already installed"
    fi
}

# Install JetBrainsMono — SOLO desde repos, nada compilado ni descargado.
# - Arch: ttf-jetbrains-mono-nerd (parcheada Nerd, con iconos) desde [extra].
# - Debian: solo existe fonts-jetbrains-mono (normal, SIN iconos Nerd).
#   Se instala esa y se avisa: para iconos Nerd completos usar Arch o
#   instalar la Nerd manualmente.
install_nerdfonts() {
    log_info "Checking JetBrainsMono..."

    if fc-list 2>/dev/null | grep -qi "JetBrainsMono"; then
        log_info "JetBrainsMono ya instalada, salto."
        return 0
    fi

    if [ "$OS" = "debian" ]; then
        sudo apt install -y fonts-jetbrains-mono fontconfig \
            || { log_warn "Fuente falló, se omite."; return 0; }
        fc-cache -f >/dev/null 2>&1 || true
        log_warn "En Debian se instaló la JetBrainsMono NORMAL (apt no tiene la Nerd). Los iconos Nerd de starship/tmux pueden faltar."
        log_success "JetBrainsMono (normal) instalada vía apt."
    elif [ "$OS" = "arch" ]; then
        sudo pacman -S --noconfirm ttf-jetbrains-mono-nerd \
            || { log_warn "Fuente falló, se omite."; return 0; }
        fc-cache -f >/dev/null 2>&1 || true
        log_success "JetBrainsMono Nerd instalada vía pacman."
    fi
}

# Setup bash autocomplete
setup_autocomplete() {
    log_info "Setting up bash autocomplete..."
    
    SHELL_RC="$HOME/.bashrc"
    
    # FZF completion and keybindings
    if ! grep -q "fzf completion" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# FZF autocomplete and keybindings" >> "$SHELL_RC"
        echo "[ -f /usr/share/bash-completion/completions/fzf ] && source /usr/share/bash-completion/completions/fzf" >> "$SHELL_RC"
        echo "[ -f /usr/share/fzf/completion.bash ] && source /usr/share/fzf/completion.bash" >> "$SHELL_RC"
        echo "[ -f /usr/share/fzf/key-bindings.bash ] && source /usr/share/fzf/key-bindings.bash" >> "$SHELL_RC"
    fi

    # Starship completion
    if ! grep -q "starship completions bash" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# Starship autocomplete" >> "$SHELL_RC"
        echo "source <(starship completions bash)" >> "$SHELL_RC"
    fi

    # GitHub CLI (gh) completion
    if ! grep -q "gh completion" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# GitHub CLI autocomplete" >> "$SHELL_RC"
        echo "source <(gh completion -s bash)" >> "$SHELL_RC"
    fi

    # HSTR completion
    if ! grep -q "hstr --show-bash-configuration" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# HSTR autocomplete" >> "$SHELL_RC"
        echo "source <(hstr --show-bash-configuration)" >> "$SHELL_RC"
    fi
    
    log_success "Bash autocomplete configured in $SHELL_RC"
}

# Install kitty (terminal por defecto de shell-workflow)
install_kitty() {
    if command -v kitty &> /dev/null; then
        log_info "kitty ya instalado, salto."
        return 0
    fi
    log_info "Installing kitty..."
    if [ "$OS" = "debian" ]; then
        sudo apt install -y kitty \
            && log_success "kitty installed" \
            || log_warn "kitty falló, se omite."
    elif [ "$OS" = "arch" ]; then
        sudo pacman -S --noconfirm kitty \
            && log_success "kitty installed" \
            || log_warn "kitty falló, se omite."
    fi
}

# Install cava (visualizador de audio para la terminal)
install_cava() {
    if command -v cava &> /dev/null; then
        log_info "cava ya instalado, salto."
        return 0
    fi
    log_info "Installing cava..."
    if [ "$OS" = "debian" ]; then
        sudo apt install -y cava \
            && log_success "cava installed" \
            || log_warn "cava falló, se omite."
    elif [ "$OS" = "arch" ]; then
        sudo pacman -S --noconfirm cava \
            && log_success "cava installed" \
            || log_warn "cava falló, se omite."
    fi
}

# Install chafa (imagen -> texto: logos png/gif de fastfetch en cualquier terminal)
install_chafa() {
    if command -v chafa &> /dev/null; then
        log_info "chafa ya instalado, salto."
        return 0
    fi
    log_info "Installing chafa..."
    if [ "$OS" = "debian" ]; then
        sudo apt install -y chafa \
            && log_success "chafa installed" \
            || log_warn "chafa falló, se omite."
    elif [ "$OS" = "arch" ]; then
        sudo pacman -S --noconfirm chafa \
            && log_success "chafa installed" \
            || log_warn "chafa falló, se omite."
    fi
}

# Set kitty como terminal por defecto del sistema (x-terminal-emulator).
# El `export TERMINAL="kitty"` va en el .bashrc del repo (install.sh lo copia).
set_default_terminal() {
    if ! command -v kitty &> /dev/null; then
        log_warn "kitty no instalado, no puedo ponerlo por defecto."
        return 0
    fi
    if command -v update-alternatives &> /dev/null; then
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50 >/dev/null 2>&1 || true
        if sudo update-alternatives --set x-terminal-emulator /usr/bin/kitty >/dev/null 2>&1; then
            log_success "kitty como x-terminal-emulator por defecto"
        else
            log_warn "No se pudo fijar x-terminal-emulator (¿sin sudo?)."
        fi
    else
        log_warn "Sin update-alternatives, solo queda export TERMINAL=kitty."
    fi
}

# Setup starship prompt
setup_starship() {
    log_info "Setting up starship prompt..."
    
    SHELL_RC="$HOME/.bashrc"
    
    if [ -n "$SHELL_RC" ]; then
        if ! grep -q "starship init" "$SHELL_RC"; then
            echo "" >> "$SHELL_RC"
            echo "# Starship prompt" >> "$SHELL_RC"
            echo "eval \"\$(starship init bash)\"" >> "$SHELL_RC"
            log_success "Starship added to $SHELL_RC"
        else
            log_info "Starship already configured in $SHELL_RC"
        fi
    fi
}

# Main installation flow
main() {
    echo "========================================"
    echo "  Terminal Utils Installer"
    echo "========================================"
    echo ""
    
    detect_os
    update_packages
    install_core_tools
    install_ascii_tools
    install_music_players
    install_kew
    install_tpm
    install_fastfetch
    install_nerdfonts
    install_kitty
    install_cava
    install_chafa
    set_default_terminal
    setup_autocomplete
    setup_starship
    
    echo ""
    echo "========================================"
    echo "  Installation Complete"
    echo "========================================"
    echo ""
    echo "Installed tools (solo repos, nada compilado):"
    echo "  Core: fzf, starship, timg, tmux, mpd, playerctl, 7zip, gh, hstr"
    echo "  ASCII: cmatrix, pipes-sh, cbonsai, figlet, lolcat (+asciiquarium solo Arch)"
    echo "  Música: spotify-player, rmpc, termusic (solo Arch, en Debian se omiten)"
    echo "  File manager: yazi (Arch, desde repo) / lf (Debian, desde repo)"
    echo "  Reproductor C: kew (desde repo)"
    echo "  Terminal: kitty (por defecto, TERMINAL=kitty), cava, chafa"
    echo "  Other: TPM (git clone, sin compilar), fastfetch, bash-completion, JetBrainsMono (Nerd en Arch / normal en Debian)"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your terminal or run: source ~/.bashrc"
    echo "  2. For tmux plugins, press Ctrl+b then I inside tmux"
    echo ""
}

# Run main function
main "$@"
