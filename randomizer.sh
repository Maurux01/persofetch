#!/usr/bin/env bash
# ff-random — fastfetch randomizer para kitty (png / gif / video / ascii)
# Cada invocación elige un archivo aleatorio de utils/ y lo muestra con fastfetch.
# Uso: randomizer.sh [args extra de fastfetch]
# Si se pasa --logo / --logo-type explícito, se respeta y no se aleatoriza.

set -u

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

# ──2. Config base ─────────────────────────────────────────────
FF_BIN="$(command -v fastfetch)"
BASE_CONFIG=""
for cfg in "$HOME/.config/fastfetch/config.jsonc" "$_SCRIPT_DIR/fastfetch/config.jsonc"; do
    if [[ -f "$cfg" ]]; then BASE_CONFIG="$cfg"; break; fi
done

# Si el usuario ya pidió un logo explícito, no aleatorizar
for a in "$@"; do
    case "$a" in
        --logo|--logo-type|--logo-position|-l) command fastfetch "$@"; exit $? ;;
        --logo=*|--logo-type=*)                command fastfetch "$@"; exit $? ;;
    esac
done

# ──3. Construir pool: pngs + gifs + ascii + videos ────────────
shopt -s nullglob nocaseglob
IMGS=("$UTILS_BASE"/icons/*.png "$UTILS_BASE"/icons/*.jpg "$UTILS_BASE"/icons/*.jpeg "$UTILS_BASE"/icons/*.webp)
GIFS=("$UTILS_BASE"/gifs/*.gif)
VIDS=("$UTILS_BASE"/videos/*.mp4 "$UTILS_BASE"/videos/*.mkv "$UTILS_BASE"/videos/*.webm "$UTILS_BASE"/videos/*.mov)
TXTS=("$UTILS_BASE"/ASCII/*.txt "$UTILS_BASE"/ascii/*.txt)
# Compat: estructura vieja ~/.config/fastfetch/logos/[0-9]*.png
LEGACY=("$UTILS_BASE"/[0-9]*.png "$UTILS_BASE"/*.png "$UTILS_BASE"/*.gif)
shopt -u nocaseglob
# Filtrar enlaces rotos / vacíos por categoría
for arr in IMGS GIFS VIDS TXTS LEGACY; do
    # shellcheck disable=SC1087
    eval "TMP=(); for f in \"\${${arr}[@]}\"; do [[ -f \"\$f\" && -s \"\$f\" ]] && TMP+=(\"\$f\"); done; ${arr}=(\"\${TMP[@]}\")"
done
# Categorías no vacías (balancea png/gif/txt/video en vez de puro peso por cantidad)
CATS=()
(( ${#IMGS[@]} > 0 )) && CATS+=("IMGS")
(( ${#GIFS[@]} > 0 )) && CATS+=("GIFS")
(( ${#VIDS[@]} > 0 )) && CATS+=("VIDS")
(( ${#TXTS[@]} > 0 )) && CATS+=("TXTS")
(( ${#LEGACY[@]} > 0 )) && CATS+=("LEGACY")
POOL=("${IMGS[@]}" "${GIFS[@]}" "${VIDS[@]}" "${TXTS[@]}" "${LEGACY[@]}")

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
if (( ${#CATS[@]} > 1 )); then
    if command -v shuf >/dev/null 2>&1; then
        CHOSEN_CAT="$(printf '%s\n' "${CATS[@]}" | shuf -n 1)"
    else
        CHOSEN_CAT="${CATS[$(( RANDOM % ${#CATS[@]} ))]}"
    fi
    PICK="$(_pick_from "$CHOSEN_CAT")"
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

# Tipo de logo según extensión + terminal
# kitty es el default pedido; fuera de kitty usamos auto para no romper sixel/iterm
LOGO_TYPE="kitty"
if [[ "${TERM:-}" != *kitty* && -z "${KITTY_WINDOW_ID:-}" ]]; then
    # fastfetch --logo-type auto detecta kitty/sixel/iterm; para txt usamos file
    case "$EXT" in
        txt|ascii) LOGO_TYPE="file" ;;
        *)         LOGO_TYPE="auto"  ;;
    esac
else
    case "$EXT" in
        txt|ascii) LOGO_TYPE="file" ;;
        *)         LOGO_TYPE="kitty" ;;
    esac
fi

LOGO_SOURCE="$PICK"

# ──5. Videos: extraer thumbnail con ffmpeg ────────────────────
# fastfetch no reproduce video, así que mostramos el primer frame en kitty.
case "$EXT" in
    mp4|mkv|webm|mov|avi)
        THUMB="${TMPDIR:-/tmp}/ff-random-thumb-$UID.png"
        if command -v ffmpeg >/dev/null 2>&1; then
            if ffmpeg -y -loglevel error -i "$PICK" -vframes 1 "$THUMB" 2>/dev/null && [[ -s "$THUMB" ]]; then
                LOGO_SOURCE="$THUMB"
                [[ "$LOGO_TYPE" == "file" ]] && LOGO_TYPE="kitty"
                if [[ "${TERM:-}" != *kitty* && -z "${KITTY_WINDOW_ID:-}" ]]; then LOGO_TYPE="auto"; else LOGO_TYPE="kitty"; fi
            else
                echo "[ff-random] ffmpeg no pudo extraer frame de $PICK, elijo otro" >&2
                # reintento simple con imagen fija
                IMGS=()
                for f in "${POOL[@]}"; do
                    case "${f##*.}" in [Pp][Nn][Gg]|[Jj][Pp][Gg]|[Gg][Ii][Ff]) IMGS+=("$f") ;; esac
                done
                (( ${#IMGS[@]} > 0 )) && LOGO_SOURCE="${IMGS[$(( RANDOM % ${#IMGS[@]} ))]}" || LOGO_SOURCE="$PICK"
            fi
        else
            echo "[ff-random] ffmpeg no instalado, omito video $PICK" >&2
            IMGS=()
            for f in "${POOL[@]}"; do
                case "${f##*.}" in [Pp][Nn][Gg]|[Jj][Pp][Gg]|[Gg][Ii][Ff]|[Tt][Xx][Tt]) IMGS+=("$f") ;; esac
            done
            if (( ${#IMGS[@]} > 0 )); then
                LOGO_SOURCE="${IMGS[$(( RANDOM % ${#IMGS[@]} ))]}"
                case "$LOGO_SOURCE" in *.txt|*.TXT) LOGO_TYPE="file" ;; *) LOGO_TYPE="kitty" ;; esac
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
# echo "[ff-random] $LOGO_TYPE :: $LOGO_SOURCE" >&2  # descomenta para debug
if [[ -n "$BASE_CONFIG" ]]; then
    command fastfetch --config "$BASE_CONFIG" --logo-type "$LOGO_TYPE" --logo "$LOGO_SOURCE" "$@"
    exit $?
else
    command fastfetch --logo-type "$LOGO_TYPE" --logo "$LOGO_SOURCE" "$@"
    exit $?
fi
