#!/usr/bin/env bash
#
# shell-workflow :: install.sh
# Instalador interactivo de dotfiles.
#
# Flujo pedido:
#   1. Pregunta si quieres instalar herramientas (tools.sh).
#      - Si SÍ   -> corre tools.sh y luego copia configs.
#      - Si NO   -> solo copia/pega configs a sus rutas default.
#   2. Copia y reemplaza CADA archivo de tmux / starship / kitty / fastfetch
#      a donde debe ir (modos copiar + reemplazar).
#      - Si la carpeta/archivo default no existe -> la crea.
#      - Si ya existe -> pregunta si deseas sobreescribirlo.
#        Respuestas: s = sobreescribir, n = saltar ese archivo,
#                    c = cancelar TODO y salir.
#      - Con --yes se sobreescribe todo sin preguntar.
#   3. fastfetch (caso especial):
#      a) genera la config default con su propio comando
#         (`fastfetch --gen-config`),
#      b) copia y reemplaza CADA archivo de fastfetch/ del repo
#         a ~/.config/fastfetch/ (config.jsonc, etc.),
#      c) mete `utils/` dentro de `~/.config/fastfetch/utils`
#         para que fastfetch/randomizer los lea desde ahí.
#   4. .bashrc (reemplazo total):
#      - Copia y reemplaza ~/.bashrc (carpeta raíz del usuario en Linux,
#        $HOME) con el .bashrc que está en la carpeta shell-workflow
#        (este repo). Hace backup del anterior a ~/.bashrc.bak.
#
# Uso:
#   ./install.sh
#   ./install.sh --yes            # sobreescribe todo sin preguntar
#   ./install.sh --with-tools     # corre tools.sh sin preguntar
#   ./install.sh --skip-tools     # no corre tools.sh sin preguntar
#   ./install.sh --only=fastfetch # solo instala ese módulo
#   ./install.sh -h | --help

set -u

# ── Colores / log ────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
AUTO_YES=0
WITH_TOOLS=""   # "" = preguntar, "yes"/"no" = forzado
ONLY=""         # "" = todo, o lista separada por comas: tmux,starship,kitty,cava,fastfetch,bashrc,randomizer
CANCELLED=0

usage() {
    sed -n '2,30p' "$0"
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        -y|--yes|--force) AUTO_YES=1 ;;
        --with-tools) WITH_TOOLS="yes" ;;
        --skip-tools|--no-tools) WITH_TOOLS="no" ;;
        --only=*) ONLY="${arg#--only=}" ;;
    esac
done

wants_module() { # $1 = nombre módulo
    [[ -z "$ONLY" ]] && return 0
    case ",$ONLY," in *",${1},"*) return 0 ;; *) return 1 ;; esac
}

# ── Preguntas ────────────────────────────────────────────────
ask_yes_no() { # $1 = pregunta, $2 = default (y/n)
    local prompt="$1" def="${2:-n}" ans
    if (( AUTO_YES )); then return 0; fi
    if [[ "$def" == "y" ]]; then prompt="$prompt [S/n]: "
    else prompt="$prompt [s/N]: "; fi
    read -r -p "$prompt" ans || ans=""
    ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$ans" ]]; then [[ "$def" == "y" ]]; return
    fi
    [[ "$ans" == "s" || "$ans" == "si" || "$ans" == "sí" || "$ans" == "y" || "$ans" == "yes" ]]
}

# Pregunta de sobreescritura con triple opción.
# Retorna: 0 = sobreescribir, 1 = saltar, 2 = cancelar todo
ask_overwrite() { # $1 = ruta destino legible
    local dest="$1" ans
    if (( AUTO_YES )); then return 0; fi
    echo -e "${YELLOW}[EXISTE]${NC} $dest ya existe."
    read -r -p "  ¿Sobreescribir? [s]í / [n]o saltar / [c]ancelar todo: " ans || ans="c"
    ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
    case "$ans" in
        s|si|sí|y|yes) return 0 ;;
        n|no)          return 1 ;;
        *)             return 2 ;;
    esac
}

cancel_all() {
    CANCELLED=1
    log_warn "Instalación cancelada por el usuario. No se hicieron más cambios."
    exit 130
}

# ── Copiado con creación + pregunta ──────────────────────────
# copy_file <origen> <destino>
copy_file() {
    local src="$1" dest="$2" rc
    if [[ ! -f "$src" ]]; then
        log_warn "Origen no encontrado, salto: $src"
        return 0
    fi
    mkdir -p "$(dirname "$dest")" || { log_error "No pude crear $(dirname "$dest")"; return 1; }
    if [[ -f "$dest" ]]; then
        if cmp -s "$src" "$dest"; then
            log_info "Igual, salto: $dest"
            return 0
        fi
        ask_overwrite "$dest"; rc=$?
        if (( rc == 0 )); then
            cp -f "$src" "$dest" && log_success "Sobrescrito: $dest"
        elif (( rc == 1 )); then
            log_info "Saltado (no): $dest"
        else
            cancel_all
        fi
    else
        cp "$src" "$dest" && log_success "Creado: $dest"
    fi
}

# copy_file_sys <origen> <destino>
# Igual que copy_file pero con sudo (para /usr/local/bin).
# Si no hay sudo o falla, avisa y sigue (no cancela todo).
copy_file_sys() {
    local src="$1" dest="$2" rc
    if [[ ! -f "$src" ]]; then
        log_warn "Origen no encontrado, salto: $src"
        return 0
    fi
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        log_info "Igual, salto: $dest"
        return 0
    fi
    if [[ -f "$dest" ]]; then
        ask_overwrite "$dest (sistema)"; rc=$?
        if (( rc == 1 )); then
            log_info "Saltado (no): $dest"
            return 0
        elif (( rc != 0 )); then
            cancel_all
        fi
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$(dirname "$dest")" || { log_error "No pude crear $(dirname "$dest")"; return 1; }
        if sudo cp -f "$src" "$dest" && sudo chmod +x "$dest"; then
            log_success "Instalado a nivel sistema: $dest"
        else
            log_warn "No se pudo escribir $dest (¿sin sudo?). Sigo con ~/.local/bin."
            return 1
        fi
    else
        log_warn "Sin sudo, no puedo escribir $dest. Sigo con ~/.local/bin."
        return 1
    fi
}
# Copia el CONTENIDO (para utils/). Pregunta una sola vez si el destino existe y no está vacío.
copy_dir_contents() {
    local src_dir="$1" dest_dir="$2" rc
    if [[ ! -d "$src_dir" ]]; then
        log_warn "Origen no encontrado, salto: $src_dir"
        return 0
    fi
    if [[ ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir" || { log_error "No pude crear $dest_dir"; return 1; }
        log_info "Carpeta creada: $dest_dir"
    fi
    if [[ -n "$(ls -A "$dest_dir" 2>/dev/null)" ]]; then
        ask_overwrite "$dest_dir/ (contenido existente)"; rc=$?
        if (( rc == 1 )); then
            log_info "Saltado (no): $dest_dir/"
            return 0
        elif (( rc != 0 )); then
            cancel_all
        fi
        log_info "Sincronizando $src_dir/ -> $dest_dir/ ..."
    else
        log_info "Copiando $src_dir/ -> $dest_dir/ ..."
    fi
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$src_dir"/ "$dest_dir"/ && log_success "Sincronizado: $dest_dir/"
    else
        cp -a "$src_dir"/. "$dest_dir"/ && log_success "Copiado: $dest_dir/"
    fi
}

# Copia y reemplaza CADA archivo (top-level, incluye dotfiles) de
# <src_dir> a <dest_dir>, manteniendo el mismo nombre.
# copy_all_files <src_dir> <dest_dir>
copy_all_files() {
    local src_dir="$1" dest_dir="$2" f base
    if [[ ! -d "$src_dir" ]]; then
        log_warn "Origen no encontrado, salto: $src_dir"
        return 0
    fi
    mkdir -p "$dest_dir" || { log_error "No pude crear $dest_dir"; return 1; }
    local count=0
    for f in "$src_dir"/* "$src_dir"/.*; do
        [[ -e "$f" ]] || continue
        base="$(basename "$f")"
        [[ "$base" == "." || "$base" == ".." ]] && continue
        [[ -f "$f" ]] || { log_info "Salto (no es archivo): $f"; continue; }
        copy_file "$f" "$dest_dir/$base"
        ((count++)) || true
    done
    (( count == 0 )) && log_warn "No había archivos para copiar en: $src_dir"
}
# ── Paso 1: ¿instalar herramientas? ──────────────────────────
maybe_run_tools() {
    wants_module "tools" || { log_info "--only: salto tools.sh"; return 0; }
    local run_tools=0
    if [[ "$WITH_TOOLS" == "yes" ]]; then
        run_tools=1
    elif [[ "$WITH_TOOLS" == "no" ]]; then
        run_tools=0
    else
        echo ""
        echo "¿Quieres instalar las herramientas con tools.sh"
        echo "(fzf, starship, tmux, fastfetch, yazi [Arch] / lf [Debian], pipes.sh, etc.)?"
        if ask_yes_no "  Instalar tools.sh" "n"; then run_tools=1; fi
    fi
    if (( run_tools )); then
        if [[ ! -f "$REPO_DIR/tools.sh" ]]; then
            log_error "No existe $REPO_DIR/tools.sh, no puedo instalar herramientas."
            exit 1
        fi
        log_info "Corriendo tools.sh ..."
        bash "$REPO_DIR/tools.sh" || { log_error "tools.sh falló."; exit 1; }
    else
        log_info "Salto tools.sh: solo se copiarán los archivos de configuración."
    fi
}

# ── Paso 2: módulos simples ──────────────────────────────────
install_tmux() {
    wants_module "tmux" || return 0
    log_info "== tmux (copiar y reemplazar cada archivo a \$HOME) =="
    # Cada archivo de tmux/ -> $HOME con el mismo nombre
    # (.tmux.conf -> ~/.tmux.conf, etc.)
    copy_all_files "$REPO_DIR/tmux" "$HOME"
}

install_starship() {
    wants_module "starship" || return 0
    log_info "== starship =="
    # Ruta default de starship: ~/.config/starship.toml
    copy_file "$REPO_DIR/starship/starship.toml" "$HOME/.config/starship.toml"
}

install_kitty() {
    wants_module "kitty" || return 0
    log_info "== kitty =="
    copy_file "$REPO_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
}

install_cava() {
    wants_module "cava" || return 0
    log_info "== cava =="
    # Ruta default de cava: ~/.config/cava/config
    copy_file "$REPO_DIR/cava/config" "$HOME/.config/cava/config"
}

# ── Paso 3: fastfetch (gen default -> reemplazo -> utils) ────
install_fastfetch() {
    wants_module "fastfetch" || return 0
    log_info "== fastfetch =="
    local dest_dir="$HOME/.config/fastfetch"
    local dest_cfg="$dest_dir/config.jsonc"
    local repo_cfg="$REPO_DIR/fastfetch/config.jsonc"

    # 3.0 La carpeta default se crea si no existe
    if [[ ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir" && log_success "Carpeta creada: $dest_dir"
    fi

    # 3.a Generar la config default con su propio comando.
    #     Esto valida que fastfetch existe y deja la estructura default.
    #     Se pasa ruta explícita porque `fastfetch --gen-config` a secas
    #     falla si ya existe el archivo (exit 221) y respeta $HOME.
    if command -v fastfetch >/dev/null 2>&1; then
        if [[ ! -f "$dest_cfg" ]]; then
            log_info "Generando config default con: fastfetch --gen-config \"$dest_cfg\" ..."
            if fastfetch --gen-config "$dest_cfg" >/dev/null 2>&1; then
                log_success "Config default generada en $dest_cfg"
            else
                log_warn "fastfetch --gen-config falló; se copiará la del repo directamente."
            fi
        else
            log_info "Ya existe $dest_cfg, no regenero el default (se decidirá al reemplazar)."
        fi
    else
        log_warn "fastfetch no está instalado (corre con --with-tools para instalarlo). Se copiará la config igual."
    fi

    # 3.b Copiar y reemplazar CADA archivo de fastfetch/ del repo
    #     a ~/.config/fastfetch/ (config.jsonc y los que haya).
    #     Pregunta si ya existe y difiere (vía copy_file).
    copy_all_files "$REPO_DIR/fastfetch" "$dest_dir"

    # 3.c Meter utils/ dentro de la carpeta fastfetch del equipo
    #     para que fastfetch/randomizer los lea desde ahí.
    if [[ -d "$REPO_DIR/utils" ]]; then
        copy_dir_contents "$REPO_DIR/utils" "$dest_dir/utils"
        # Compat: el randomizer también mira ~/.config/fastfetch/logos
        mkdir -p "$dest_dir/logos" 2>/dev/null || true
        log_info "utils disponible en: $dest_dir/utils (icons/ gifs/ ASCII/ videos/)"
    else
        log_warn "No existe $REPO_DIR/utils, salto ese paso."
    fi
}

# ── Paso 4: randomizer + .bashrc ─────────────────────────────
install_randomizer() {
    wants_module "randomizer" || return 0
    log_info "== randomizer =="
    if [[ -f "$REPO_DIR/randomizer.sh" ]]; then
        chmod +x "$REPO_DIR/randomizer.sh" || true
        mkdir -p "$HOME/.local/bin" || true
        copy_file "$REPO_DIR/randomizer.sh" "$HOME/.local/bin/ff-random"
        chmod +x "$HOME/.local/bin/ff-random" 2>/dev/null || true
    else
        log_warn "No existe $REPO_DIR/randomizer.sh, salto."
    fi
}

install_bashrc() {
    wants_module "bashrc" || return 0
    log_info "== bashrc (copiar y reemplazar ~/.bashrc con el del repo) =="
    local src="$REPO_DIR/.bashrc"
    local rc="$HOME/.bashrc"
    if [[ ! -f "$src" ]]; then
        log_warn "Origen no encontrado, salto: $src"
        return 0
    fi
    if [[ -f "$rc" ]] && ! cmp -s "$src" "$rc"; then
        # Backup del .bashrc anterior antes de reemplazar
        local bak="$HOME/.bashrc.bak"
        cp -f "$rc" "$bak" 2>/dev/null \
            && log_info "Backup del .bashrc anterior en: $bak" \
            || log_warn "No pude crear backup en $bak, sigo igual."
    fi
    # Copia y reemplaza: shell-workflow/.bashrc -> ~/.bashrc
    # (carpeta raíz del usuario en Linux = $HOME).
    # copy_file ya crea, compara, pregunta s/n/c o sobreescribe con --yes.
    copy_file "$src" "$rc"
}

# ── Main ─────────────────────────────────────────────────────
main() {
    echo "========================================"
    echo "  shell-workflow :: install.sh"
    echo "  Repo: $REPO_DIR"
    echo "========================================"
    echo ""

    maybe_run_tools
    echo ""
    install_tmux
    echo ""
    install_starship
    echo ""
    install_kitty
    echo ""
    install_cava
    echo ""
    install_fastfetch
    echo ""
    install_randomizer
    echo ""
    install_bashrc

    echo ""
    echo "========================================"
    echo "  Instalación de dotfiles completa"
    echo "========================================"
    echo ""
    echo "Siguiente:"
    echo "  1. source ~/.bashrc"
    echo "  2. Abre kitty y corre: fastfetch  (cada llamada rota png/gif/txt/video)"
    echo "  3. Si algo no se copió, re-corre con: ./install.sh --only=fastfetch"
    echo ""
}

main "$@"
