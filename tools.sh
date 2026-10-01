#!/bin/bash

# Terminal Utils Installer
# Installs tools from GitHub Stars list + ASCII terminal utilities
# Supports Debian/Ubuntu and Arch Linux

set -u
# NOTA: no usamos `set -e` a propósito: las herramientas ASCII / cargo / kew
# son opcionales y un fallo puntual (paquete ausente, /tmp sucio, error de
# compilación) no debe abortar toda la instalación.

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
        || log_warn "Algún paquete core falló (ver arriba). Sigo con el resto."
        
        log_warn "Some tools (yazi, spotify-player, rmpc, termusic, kew) are not in default Debian repos."
        log_info "They will be installed via cargo or compiled from source in the next steps."
        
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
        || log_warn "Algún paquete core falló, sigo igual."
    fi
}

# Install ASCII terminal utilities
install_ascii_tools() {
    log_info "Installing ASCII terminal utilities..."
    
    if [ "$OS" = "debian" ]; then
        # asciiquarium NO existe en los repos Debian -> se omite (no debe
        # tumbar el apt completo). cmatrix/figlet/lolcat ya vienen de core.
        sudo apt install -y \
            cmatrix \
            figlet \
            toilet \
            lolcat \
        || log_warn "Algún paquete ASCII falló, sigo igual."
        log_warn "asciiquarium no está en repos Debian, se omite."

        # Install pipes.sh from source
        if [ ! -f /usr/local/bin/pipes.sh ]; then
            log_info "Installing pipes.sh from source..."
            rm -rf /tmp/pipes.sh
            if git clone https://github.com/pipeseroni/pipes.sh.git /tmp/pipes.sh; then
                sudo cp /tmp/pipes.sh/pipes.sh /usr/local/bin/pipes.sh \
                    && sudo chmod +x /usr/local/bin/pipes.sh \
                    && log_success "pipes.sh installed" \
                    || log_warn "No se pudo copiar pipes.sh a /usr/local/bin."
            else
                log_warn "No se pudo clonar pipes.sh, se omite."
            fi
            rm -rf /tmp/pipes.sh
        fi

        # Install cbonsai from source
        if ! command -v cbonsai &> /dev/null; then
            log_info "Installing cbonsai from source..."
            rm -rf /tmp/cbonsai
            if git clone https://gitlab.com/jallbrit/cbonsai.git /tmp/cbonsai; then
                (cd /tmp/cbonsai && sudo make install) \
                    && log_success "cbonsai installed" \
                    || log_warn "make install de cbonsai falló, se omite."
            else
                log_warn "No se pudo clonar cbonsai, se omite."
            fi
            rm -rf /tmp/cbonsai
        fi
        
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

# Install Rust-based tools via cargo
install_cargo_tools() {
    log_info "Checking for Rust toolchain..."

    if ! command -v cargo &> /dev/null; then
        log_warn "Rust not found. Installing rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
            || { log_warn "rustup falló, salto herramientas cargo."; return 0; }
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
    fi

    export PATH="$HOME/.cargo/bin:$PATH"

    log_info "Installing Rust-based tools via cargo..."

    # Install yazi on Debian (Arch has it in repos)
    if [ "$OS" = "debian" ]; then
        if ! command -v yazi &> /dev/null; then
            log_info "Installing yazi..."
            cargo install yazi-fm yazi-cli \
                || log_warn "yazi falló (faltan deps o ya instalado). Sigo igual."
        fi
    fi

    # Install other rust tools
    cargo install --locked \
        spotify_player \
        rmpc \
        termusic 2>/dev/null || log_warn "Some cargo packages may have failed (already installed or build errors)"
}

# Install kew (C-based music player)
install_kew() {
    if command -v kew &> /dev/null; then
        log_info "kew ya instalado, salto."
        return 0
    fi
    log_info "Installing kew (music player)..."

    if [ "$OS" = "debian" ]; then
        sudo apt install -y build-essential libncurses-dev libasound2-dev \
            || log_warn "Deps de kew fallaron, intento compilar igual."
    elif [ "$OS" = "arch" ]; then
        sudo pacman -S --noconfirm base-devel ncurses alsa-lib \
            || log_warn "Deps de kew fallaron, intento compilar igual."
    fi

    rm -rf /tmp/kew
    if ! git clone https://github.com/ravachol/kew.git /tmp/kew; then
        log_warn "No se pudo clonar kew, se omite."
        rm -rf /tmp/kew
        return 0
    fi
    if (cd /tmp/kew && make); then
        (cd /tmp/kew && sudo make install) \
            && log_success "kew installed" \
            || log_warn "make install de kew falló, se omite."
    else
        log_warn "make de kew falló, se omite."
    fi
    rm -rf /tmp/kew
}

# Install Tmux Plugin Manager
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

# Install best Nerd Font: JetBrainsMono Nerd Font
# - La mejor para terminal/dev: legible, ligaduras, iconos perfectos
#   para starship/tmux/fastfetch/kitty.
# - Idempotente: si ya existe en fc-list, salta.
# - Instalación a nivel usuario: ~/.local/share/fonts (sin sudo,
#   funciona en Debian/Arch/Kali/WSL).
install_nerdfonts() {
    local font_name="JetBrainsMono"
    local font_dir="$HOME/.local/share/fonts/$font_name"
    local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font_name}.zip"
    local tmp_zip="/tmp/${font_name}.zip"

    log_info "Checking Nerd Font ($font_name)..."

    if fc-list 2>/dev/null | grep -qi "${font_name}.*Nerd"; then
        log_info "Nerd Font $font_name ya instalada, salto."
        return 0
    fi

    # Deps mínimas para descargar/descomprimir/cachear fuentes
    if ! command -v unzip &> /dev/null || ! command -v fc-cache &> /dev/null || ! command -v curl &> /dev/null; then
        log_info "Instalando dependencias de fuentes (unzip, fontconfig, curl)..."
        if [ "$OS" = "debian" ]; then
            sudo apt install -y unzip fontconfig curl \
                || log_warn "Deps de fuentes fallaron, intento seguir igual."
        elif [ "$OS" = "arch" ]; then
            sudo pacman -S --noconfirm unzip fontconfig curl \
                || log_warn "Deps de fuentes fallaron, intento seguir igual."
        fi
    fi

    mkdir -p "$font_dir" || { log_error "No pude crear $font_dir"; return 1; }

    log_info "Descargando $font_name Nerd Font (latest)..."
    rm -f "$tmp_zip"
    if ! curl -fLo "$tmp_zip" --retry 3 "$url"; then
        log_error "No se pudo descargar $url"
        return 1
    fi

    log_info "Instalando en $font_dir ..."
    if ! unzip -o -q "$tmp_zip" -d "$font_dir"; then
        log_error "No se pudo descomprimir $tmp_zip"
        rm -f "$tmp_zip"
        return 1
    fi
    rm -f "$tmp_zip"

    log_info "Regenerando caché de fuentes (fc-cache)..."
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 \
        || fc-cache -f >/dev/null 2>&1 \
        || log_warn "fc-cache falló, la fuente igual quedó copiada."

    if fc-list 2>/dev/null | grep -qi "${font_name}.*Nerd"; then
        log_success "Nerd Font $font_name instalada en $font_dir"
    else
        log_warn "Copiada en $font_dir pero fc-list aún no la ve (reabre la terminal o corre: fc-cache -fv)."
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
    install_cargo_tools
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
    echo "Installed tools:"
    echo "  Core: fzf, starship, timg, tmux, mpd, playerctl, 7zip, gh, hstr"
    echo "  ASCII: cmatrix, pipes.sh, cbonsai, figlet, lolcat,  asciiquarium"
    echo "  Rust: yazi, spotify-player, rmpc, termusic"
    echo "  C: kew"
    echo "  Terminal: kitty (por defecto, TERMINAL=kitty), cava, chafa"
    echo "  Other: TPM, fastfetch, bash-completion, JetBrainsMono Nerd Font"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your terminal or run: source ~/.bashrc"
    echo "  2. For tmux plugins, press Ctrl+b then I inside tmux"
    echo ""
}

# Run main function
main "$@"
