#!/usr/bin/env bash
# ff-random — fastfetch randomizer (png / gif / video / ascii / colorscripts)
# Cada invocación elige un archivo aleatorio de utils/ y lo muestra con fastfetch.
# kitty con gráficos -> protocolo kitty; terminal normal + chafa -> arte a color;
# sin gráficos -> ASCII (logo-type file, nunca basura binaria).
# Uso: randomizer.sh [args extra de fastfetch]
#      randomizer.sh --pool-stats          # muestra conteos por categoría y sale
#      randomizer.sh --debug               # una tirada de prueba sin ejecutar fastfetch
#      FF_CATEGORY=IMGS|GIFS|VIDS|TXTS|CS fastfetch   # fuerza una categoría (para verificar)
#      FF_FORCE_KITTY=1 / FF_FORCE_CHAFA=1 / FF_FORCE_ASCII=1  # forzar capacidad
# Si se pasa --logo / --logo-type explícito, se respeta y no se aleatoriza.

set -u

# ──0. Medida única del workflow ──────────────────────────────
# TODO logo pasa por aquí: nada supera LOGO_W x LOGO_H.
# - ASCII grandes (hasta 100 cols x 41 líneas) -> recortados a esto.
# - colorscripts small (~36x19) -> salen completos.
# - colorscripts large (~72x36) -> recortados de alto a LOGO_H; el ancho lo
#   recorta fastfetch vía logo.width (cortar ANSI con `cut` rompería colores).
# - png/gif/jpg vía chafa CLI -> --size LOGO_WxLOGO_H.
# - png/gif en kitty -> fastfetch los escala a logo.width/height del config.
# Debe coincidir con logo.width/height de fastfetch/config.jsonc.
LOGO_W=40
LOGO_H=20

# ──1. Localizar base de utils ─────────────────────────────────
# Orden: $FF_UTILS_DIR > ~/shell-workflow/utils > ~/.config/fastfetch/utils
#        > dir del script/utils > ~/.config/fastfetch/logos
_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
CANDIDATES=(
    "${FF_UTILS_DIR:-}"
    "$HOME/shell-workflow/utils"
    "$HOME/.config/fastfetch/utils"
    "$_SCRIPT_DIR/utils"
    "$HOME/.config/fastfetch/logos"
)
UTILS_BASE=""
for c in "${CANDIDATES[@]}"; do
    if [[ -n "$c" && -d "$c" ]]; then
        UTILS_BASE="$c"
        break
    fi
done
if [[ -z "$UTILS_BASE" ]]; then
    echo "[ff-random] No se encontró utils/ ni logos/, lanzo fastfetch normal" >&2
    command fastfetch "$@"
    exit $?
fi

# ──1b. Capacidades gráficas del terminal ───────────────────────
# kitty: protocolo gráfico kitty (KITTY_WINDOW_ID o KITTY_PID o TERM=*-kitty*).
# chafa: imagen -> texto a color en CUALQUIER terminal (apt install chafa).
# Sin ninguno: solo ASCII (logo-type file), png/gif saldrían como basura.
HAS_KITTY=0
if [[ -n "${KITTY_WINDOW_ID:-}" || -n "${KITTY_PID:-}" || "${TERM:-}" == *kitty* || "${TERM_PROGRAM:-}" == *kitty* ]]; then
    HAS_KITTY=1
fi
HAS_CHAFA=0
command -v chafa >/dev/null 2>&1 && HAS_CHAFA=1
# Overrides manuales (para verificar cada tipo de logo)
[[ "${FF_FORCE_KITTY:-0}" == "1" ]] && HAS_KITTY=1
[[ "${FF_FORCE_CHAFA:-0}" == "1" ]] && HAS_CHAFA=1
if [[ "${FF_FORCE_ASCII:-0}" == "1" ]]; then
    HAS_KITTY=0; HAS_CHAFA=0
fi

_logo_type_for() { # $1 = extensión (cualquier mayúsculas)
    local e="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
    case "$e" in
        txt|ascii) printf 'file' ;;
        *)
            if (( HAS_KITTY )); then printf 'kitty'
            elif (( HAS_CHAFA )); then printf 'chafa'
            else printf 'file'
            fi ;;
    esac
}

# Pre-render con chafa CLI a texto (cacheado).
# El fastfetch de Debian no trae soporte chafa compilado (--logo-type chafa
# cae al logo builtin), así que convertimos png/gif/jpg a arte ANSI y lo
# mostramos con --logo-type file. El cache evita re-renderizar cada fetch.
CHAFA_CACHE="${TMPDIR:-/tmp}/ff-random-chafa"
_chafa_render() { # $1 = imagen -> imprime ruta del txt cacheado o falla
    local src="$1" key cache
    command -v chafa >/dev/null 2>&1 || return 1
    command -v md5sum >/dev/null 2>&1 || return 1
    mkdir -p "$CHAFA_CACHE" 2>/dev/null || return 1
    key="$(printf '%s|%sx%s' "$src" "$LOGO_W" "$LOGO_H" | md5sum | cut -d' ' -f1)"
    cache="$CHAFA_CACHE/$key.txt"
    if [[ ! -s "$cache" || "$src" -nt "$cache" ]]; then
        if ! chafa --format symbols --symbols block --colors full --animate off --size "${LOGO_W}x${LOGO_H}" "$src" >"$cache" 2>/dev/null; then
            chafa --format symbols --symbols block --colors full --size "${LOGO_W}x${LOGO_H}" "$src" >"$cache" 2>/dev/null || return 1
        fi
        [[ -s "$cache" ]] || return 1
    fi
    printf '%s' "$cache"
}

# Normaliza texto/ANSI a un temporal acotado (solo agrega, no toca originales).
# Regla única: nada supera LOGO_W columnas x LOGO_H líneas.
# - Quita \r (los sprites de colorscripts vienen con CRLF).
# - Limita alto con head (los small/ ~19 líneas salen completos, large/ ~36 se recortan).
# - Limita ancho con cut SOLO si no hay secuencias ANSI: cortar un \x1b[...m
#   a mitad lo rompería y saldría basura. El ancho de los ANSI lo recorta
#   fastfetch con logo.width del config (40).
_normalize_text() { # $1 = src -> imprime ruta del temporal normalizado
    local src="$1" tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/ff-random-txt.XXXXXX")"
    if grep -q $'\x1b' -- "$src" 2>/dev/null; then
        tr -d '\r' < "$src" | head -n "$LOGO_H" > "$tmp"
    else
        head -n "$LOGO_H" -- "$src" | cut -c "1-$LOGO_W" | tr -d '\r' > "$tmp"
    fi
    [[ -s "$tmp" ]] || cp -- "$src" "$tmp"
    printf '%s' "$tmp"
}

# Fija LOGO_SOURCE/LOGO_TYPE para una ruta elegida, con chafa si aplica.
_apply_logo() { # $1 = ruta elegida
    # Sin extensión = sprite de colorscripts / arte ANSI -> normalizar + file-raw
    # (file-raw: sin reemplazo de placeholders $[1-9], las secuencias quedan intactas).
    if [[ "${1##*/}" != *.* ]]; then
        LOGO_SOURCE="$(_normalize_text "$1")"
        LOGO_TYPE="file-raw"
        return 0
    fi
    local e="$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')"
    LOGO_SOURCE="$1"
    LOGO_TYPE="$(_logo_type_for "$e")"
    # txt/ascii: normalizar tamaño (se mantiene type file para los $1..$9 de color).
    case "$e" in
        txt|ascii|ans|nfo) LOGO_SOURCE="$(_normalize_text "$1")" ;;
    esac
    if (( ! HAS_KITTY )) && (( HAS_CHAFA )); then
        case "$e" in
            png|jpg|jpeg|webp|gif)
                local r
                if r="$(_chafa_render "$1")"; then
                    LOGO_SOURCE="$r"
                    LOGO_TYPE="file"
                fi
                ;;
        esac
    fi
}

# ──2. Config base (CONFIG ÚNICA) ──────────────────────────────
FF_BIN="$(command -v fastfetch)"
BASE_CONFIG=""
for cfg in "$HOME/.config/fastfetch/config.jsonc" "$_SCRIPT_DIR/fastfetch/config.jsonc"; do
    if [[ -f "$cfg" ]]; then BASE_CONFIG="$cfg"; break; fi
done

# Flags propias (se consumen aquí, no se pasan a fastfetch)
DEBUG=0
STATS_ONLY=0
_FF_ARGS=()
for a in "$@"; do
    case "$a" in
        --debug) DEBUG=1 ;;
        --pool-stats) STATS_ONLY=1 ;;
        *) _FF_ARGS+=("$a") ;;
    esac
done
set -- "${_FF_ARGS[@]:-}"

# Si el usuario ya pidió un logo explícito, no aleatorizar
for a in "$@"; do
    case "$a" in
        --logo|--logo-type|--logo-position|-l) command fastfetch "$@"; exit $? ;;
        --logo=*|--logo-type=*)                command fastfetch "$@"; exit $? ;;
    esac
done

# ──3. Construir pool: pngs + gifs + ascii + videos + colorscripts ──
shopt -s nullglob nocaseglob
IMGS=("$UTILS_BASE"/icons/*.png "$UTILS_BASE"/icons/*.jpg "$UTILS_BASE"/icons/*.jpeg "$UTILS_BASE"/icons/*.webp)
GIFS=("$UTILS_BASE"/gifs/*.gif)
VIDS=("$UTILS_BASE"/videos/*.mp4 "$UTILS_BASE"/videos/*.mkv "$UTILS_BASE"/videos/*.webm "$UTILS_BASE"/videos/*.mov)
# ASCII: resolver el nombre real del dir (ASCII/ en el repo) UNA vez.
# (Antes había dos globs ASCII/*.txt + ascii/*.txt que con nocaseglob
#  duplicaban el pool, y en Linux la mitad eran rutas fantasma.)
_TXTS_DIR=""
for _d in ASCII ascii; do
    if [[ -d "$UTILS_BASE/$_d" ]]; then _TXTS_DIR="$UTILS_BASE/$_d"; break; fi
done
TXTS=()
[[ -n "$_TXTS_DIR" ]] && TXTS=("$_TXTS_DIR"/*.txt)
# Sprites ANSI sin extensión: colorscripts/small|large regular|shiny/*, más
# fallback genérico a 2-3 niveles por si la estructura cambia. Entran al
# sorteo mezclados como una sola categoría CS.
CS=(
    "$UTILS_BASE"/colorscripts/small/regular/*
    "$UTILS_BASE"/colorscripts/small/shiny/*
    "$UTILS_BASE"/colorscripts/large/regular/*
    "$UTILS_BASE"/colorscripts/large/shiny/*
    "$UTILS_BASE"/colorscripts/*/*/*
    "$UTILS_BASE"/colorscripts/*/*
)
# Compat: estructura vieja ~/.config/fastfetch/logos/[0-9]*.png
LEGACY=("$UTILS_BASE"/[0-9]*.png "$UTILS_BASE"/*.png "$UTILS_BASE"/*.gif)
shopt -u nocaseglob
# Sin kitty ni chafa no hay forma de mostrar png/gif/video
# (saldrían como basura binaria) -> solo ASCII del pool.
# Solución: instala chafa (tools.sh ya lo hace: sudo apt install chafa)
# o usa kitty. Con chafa las imágenes se pre-renderizan a ANSI y SÍ salen.
if (( ! HAS_KITTY )) && (( ! HAS_CHAFA )); then
    IMGS=(); GIFS=(); VIDS=(); LEGACY=()
    if (( DEBUG || STATS_ONLY )); then
        echo "[ff-random] sin kitty ni chafa: png/gif/video excluidos. Instala chafa o usa kitty." >&2
    fi
fi
# Filtrar enlaces rotos / vacíos / directorios por categoría
for arr in IMGS GIFS VIDS TXTS CS LEGACY; do
    # shellcheck disable=SC1087
    eval "TMP=(); for f in \"\${${arr}[@]}\"; do [[ -f \"\$f\" && -s \"\$f\" ]] && TMP+=(\"\$f\"); done; ${arr}=(\"\${TMP[@]}\")"
done
# Dedup: nocaseglob duplica ASCII/*.txt + ascii/*.txt (mismos archivos 2x) y los
# globs CS explícitos (small|large regular|shiny) se solapan con los genéricos.
for arr in IMGS GIFS VIDS TXTS CS LEGACY; do
    # shellcheck disable=SC1087
    eval "TMP=(); unset _SEEN; declare -A _SEEN=(); for f in \"\${${arr}[@]}\"; do [[ -z \"\${_SEEN[\"\$f\"]:-}\" ]] && { TMP+=(\"\$f\"); _SEEN[\"\$f\"]=1; }; done; ${arr}=(\"\${TMP[@]}\")"
done
# Categorías no vacías (balancea png/gif/txt/video/colorscripts en vez de
# puro peso por cantidad: con sorteo global puro los 5000+ sprites saldrían el 84%).
CATS=()
(( ${#IMGS[@]} > 0 )) && CATS+=("IMGS")
(( ${#GIFS[@]} > 0 )) && CATS+=("GIFS")
(( ${#VIDS[@]} > 0 )) && CATS+=("VIDS")
(( ${#TXTS[@]} > 0 )) && CATS+=("TXTS")
(( ${#CS[@]} > 0 )) && CATS+=("CS")
(( ${#LEGACY[@]} > 0 )) && CATS+=("LEGACY")
POOL=("${IMGS[@]}" "${GIFS[@]}" "${VIDS[@]}" "${TXTS[@]}" "${CS[@]}" "${LEGACY[@]}")

# Diagnóstico: conteos por categoría (verifica que png/gif entran al sorteo)
if (( STATS_ONLY || DEBUG )); then
    echo "[ff-random] utils=$UTILS_BASE kitty=$HAS_KITTY chafa=$HAS_CHAFA (medida ${LOGO_W}x${LOGO_H})" >&2
    echo "[ff-random] pool: IMGS=${#IMGS[@]} GIFS=${#GIFS[@]} VIDS=${#VIDS[@]} TXTS=${#TXTS[@]} CS=${#CS[@]} LEGACY=${#LEGACY[@]} TOTAL=${#POOL[@]}" >&2
    if (( STATS_ONLY )); then exit 0; fi
fi

if (( ${#POOL[@]} == 0 )); then
    echo "[ff-random] Pool vacío en $UTILS_BASE, lanzo fastfetch normal" >&2
    if [[ -n "$BASE_CONFIG" ]]; then command fastfetch --config "$BASE_CONFIG" "$@"; exit $?
    else command fastfetch "$@"; exit $?; fi
fi

# ──4. Pick aleatorio (categoría primero → rotación justa) ──────
_pick_from() { # $1 = nombre de array
    local arr_name="$1" len idx
    eval "len=\${#${arr_name}[@]}"
    (( len == 0 )) && return 1
    if command -v shuf >/dev/null 2>&1; then
        eval "printf '%s\n' \"\${${arr_name}[@]}\" | shuf -n 1"
    else
        idx=$(( RANDOM % len ))
        eval "printf '%s' \"\${${arr_name}[${idx}]}\""
    fi
}
PICK=""
# FF_CATEGORY fuerza una categoría (para verificar que cada tipo se ve bien):
#   FF_CATEGORY=IMGS fastfetch | FF_CATEGORY=GIFS fastfetch | TXTS | CS | VIDS
if [[ -n "${FF_CATEGORY:-}" ]]; then
    case "${FF_CATEGORY^^}" in
        IMGS|GIFS|VIDS|TXTS|CS|LEGACY) PICK="$(_pick_from "${FF_CATEGORY^^}" || true)" ;;
        *) echo "[ff-random] FF_CATEGORY inválida: $FF_CATEGORY (IMGS|GIFS|VIDS|TXTS|CS)" >&2 ;;
    esac
fi
if [[ -z "$PICK" ]]; then
    if (( ${#CATS[@]} > 1 )); then
        if command -v shuf >/dev/null 2>&1; then
            CHOSEN_CAT="$(printf '%s\n' "${CATS[@]}" | shuf -n 1)"
        else
            CHOSEN_CAT="${CATS[$(( RANDOM % ${#CATS[@]} ))]}"
        fi
        PICK="$(_pick_from "$CHOSEN_CAT")"
    fi
fi
# Fallback: sorteo global puro
if [[ -z "$PICK" ]]; then
    if command -v shuf >/dev/null 2>&1; then
        PICK="$(printf '%s\n' "${POOL[@]}" | shuf -n 1)"
    else
        PICK="${POOL[$(( RANDOM % ${#POOL[@]} ))]}"
    fi
fi

EXT="${PICK##*.}"
EXT="$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')"

# Tipo de logo según extensión + capacidades del terminal
# (con chafa las imágenes se pre-renderizan a texto cacheado)
_apply_logo "$PICK"

# ──5. Videos: extraer thumbnail con ffmpeg ────────────────────
# fastfetch no reproduce video, así que mostramos el primer frame en kitty.
case "$EXT" in
    mp4|mkv|webm|mov|avi)
        THUMB="${TMPDIR:-/tmp}/ff-random-thumb-$UID.png"
        if command -v ffmpeg >/dev/null 2>&1; then
            if ffmpeg -y -loglevel error -i "$PICK" -vframes 1 "$THUMB" 2>/dev/null && [[ -s "$THUMB" ]]; then
                _apply_logo "$THUMB"
            else
                echo "[ff-random] ffmpeg no pudo extraer frame de $PICK, elijo otro" >&2
                # reintento simple con imagen fija
                IMGS=()
                for f in "${POOL[@]}"; do
                    case "${f##*.}" in [Pp][Nn][Gg]|[Jj][Pp][Gg]|[Gg][Ii][Ff]|[Tt][Xx][Tt]) IMGS+=("$f") ;; esac
                done
                if (( ${#IMGS[@]} > 0 )); then
                    _apply_logo "${IMGS[$(( RANDOM % ${#IMGS[@]} ))]}"
                else
                    LOGO_SOURCE="$PICK"
                fi
            fi
        else
            echo "[ff-random] ffmpeg no instalado, omito video $PICK (sudo apt install ffmpeg)" >&2
            IMGS=()
            for f in "${POOL[@]}"; do
                case "${f##*.}" in [Pp][Nn][Gg]|[Jj][Pp][Gg]|[Gg][Ii][Ff]|[Tt][Xx][Tt]) IMGS+=("$f") ;; esac
            done
            if (( ${#IMGS[@]} > 0 )); then
                _apply_logo "${IMGS[$(( RANDOM % ${#IMGS[@]} ))]}"
            fi
        fi
        ;;
esac

# ──6. Mantener symlink current para `fastfetch` sin wrapper ──
mkdir -p "$HOME/.config/fastfetch/logos" 2>/dev/null || true
ln -sf "$LOGO_SOURCE" "$HOME/.config/fastfetch/logos/current" 2>/dev/null || true
case "$EXT" in
    png|jpg|jpeg|webp|gif) ln -sf "$LOGO_SOURCE" "$HOME/.config/fastfetch/logos/current.png" 2>/dev/null || true ;;
esac

# ──7. Ejecutar (command evita recursión con function fastfetch) ─
if (( DEBUG )); then
    echo "[ff-random] DEBUG pick=$PICK" >&2
    echo "[ff-random] DEBUG type=$LOGO_TYPE source=$LOGO_SOURCE" >&2
    echo "[ff-random] DEBUG config=${BASE_CONFIG:-<default>} (logo ${LOGO_W}x${LOGO_H})" >&2
    exit 0
fi
if [[ -n "$BASE_CONFIG" ]]; then
    command fastfetch --config "$BASE_CONFIG" --logo-type "$LOGO_TYPE" --logo "$LOGO_SOURCE" "$@"
    exit $?
else
    command fastfetch --logo-type "$LOGO_TYPE" --logo "$LOGO_SOURCE" "$@"
    exit $?
fi
