#!/usr/bin/env bash
# theme_preview.sh — Bash syntax showcase
# Covers: functions, arrays, associative arrays, string ops, process
#         substitution, here-docs, getopts, traps, coprocesses, regex

set -euo pipefail
IFS=$'\n\t'

# ── Constants ─────────────────────────────────────────────────────────────────
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${TMPDIR:-/tmp}/themepreview-$$.log"
readonly VERSION="1.0.0"

# ── Colours (only if terminal supports it) ─────────────────────────────────────
if [[ -t 1 ]] && command -v tput &>/dev/null; then
    RED="$(tput setaf 1)"   GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)" CYAN="$(tput setaf 6)"
    BOLD="$(tput bold)"      RESET="$(tput sgr0)"
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

# ── Logging ───────────────────────────────────────────────────────────────────
log()   { printf '%s [INFO]  %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf '%s%s [WARN]  %s%s\n' "$YELLOW" "$(date -Iseconds)" "$*" "$RESET" >&2; }
error() { printf '%s%s [ERROR] %s%s\n' "$RED"    "$(date -Iseconds)" "$*" "$RESET" >&2; }
die()   { error "$*"; exit 1; }

# ── Cleanup trap ──────────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    rm -f "$LOG_FILE"
    [[ $exit_code -ne 0 ]] && error "Exited with code $exit_code"
}
trap cleanup EXIT
trap 'die "Interrupted"' INT TERM

# ── Utility functions ─────────────────────────────────────────────────────────
require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
    done
}

confirm() {
    local prompt="${1:-Continue?}"
    read -r -p "${BOLD}${prompt} [y/N] ${RESET}" reply
    [[ "${reply,,}" =~ ^(y|yes)$ ]]
}

hex_to_rgb() {
    local hex="${1#\#}"
    local r g b
    r=$(( 16#${hex:0:2} ))
    g=$(( 16#${hex:2:2} ))
    b=$(( 16#${hex:4:2} ))
    printf '%d %d %d' "$r" "$g" "$b"
}

is_valid_hex() {
    [[ "$1" =~ ^#?[0-9A-Fa-f]{6}$ ]]
}

# ── Associative arrays ────────────────────────────────────────────────────────
declare -A COMMUNITY_THEMES=(
    ["dracula"]="#282a36"
    ["one-dark-pro"]="#282c34"
    ["monokai-pro"]="#272822"
    ["tokyo-night"]="#1a1b26"
    ["nord"]="#2e3440"
)

declare -A THEME_KEYWORDS=(
    ["dracula"]="#ff79c6"
    ["one-dark-pro"]="#c678dd"
    ["monokai-pro"]="#f92672"
    ["tokyo-night"]="#9d7cd8"
    ["nord"]="#81a1c1"
)

# ── String manipulation ───────────────────────────────────────────────────────
slugify() {
    local str="$1"
    str="${str,,}"                    # lowercase
    str="${str//[^a-z0-9]/-}"        # non-alnum → dash
    str="${str//--*/-}"              # collapse dashes
    str="${str#-}"; str="${str%-}"   # trim leading/trailing dashes
    printf '%s' "$str"
}

# ── Array operations ──────────────────────────────────────────────────────────
validate_palette() {
    local -n _palette="$1"   # nameref
    local min="${2:-2}"
    local errors=0

    if (( ${#_palette[@]} < min )); then
        error "Palette too small: ${#_palette[@]} colours (need ≥ $min)"
        return 1
    fi

    local colour
    for colour in "${_palette[@]}"; do
        if ! is_valid_hex "$colour"; then
            warn "Invalid hex colour: $colour"
            (( errors++ ))
        fi
    done

    (( errors == 0 ))
}

sort_by_lightness() {
    # Compute approx lightness (average of R,G,B) and sort descending
    local -n _arr="$1"
    local pair colour lightness
    local -a pairs=()

    for colour in "${_arr[@]}"; do
        read -r r g b < <(hex_to_rgb "$colour")
        lightness=$(( (r + g + b) / 3 ))
        pairs+=("$(printf '%03d %s' "$lightness" "$colour")")
    done

    mapfile -t sorted < <(printf '%s\n' "${pairs[@]}" | sort -rn)
    _arr=()
    for pair in "${sorted[@]}"; do _arr+=("${pair#* }"); done
}

# ── Here-doc ─────────────────────────────────────────────────────────────────
generate_package_json() {
    local name="$1" slug="$2" bg="$3"
    cat <<JSON
{
    "name": "${slug}",
    "displayName": "${name}",
    "version": "0.0.1",
    "publisher": "Steven-Wiener",
    "engines": { "vscode": "^1.91.1" },
    "categories": ["Themes"],
    "galleryBanner": { "color": "${bg}", "theme": "dark" },
    "contributes": {
        "themes": [{
            "label": "${name}",
            "uiTheme": "vs-dark",
            "path": "./themes/${slug}-color-theme.json"
        }]
    }
}
JSON
}

# ── Process substitution ──────────────────────────────────────────────────────
diff_palettes() {
    local -n _a="$1" _b="$2"
    diff <(printf '%s\n' "${_a[@]}") <(printf '%s\n' "${_b[@]}") || true
}

# ── getopts ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $SCRIPT_NAME [OPTIONS] <theme-name>

Generate a VS Code colour theme extension.

${BOLD}Options:${RESET}
  -p <colour,...>   Comma-separated hex palette (e.g. -p '#070425,#9900FF')
  -o <dir>          Output directory (default: ./out)
  -m <mode>         Mode: custom | random | personalized (default: custom)
  -v                Verbose output
  -h                Show this help

${BOLD}Examples:${RESET}
  $SCRIPT_NAME -p '#070425,#9900FF,#09FBD3' "Neon Vomit Night"
  $SCRIPT_NAME -m random "My Random Theme"
EOF
}

parse_args() {
    OUTPUT_DIR="./out"
    MODE="custom"
    VERBOSE=0
    PALETTE=()

    while getopts ':p:o:m:vh' opt; do
        case "$opt" in
            p)  IFS=',' read -ra PALETTE <<< "$OPTARG" ;;
            o)  OUTPUT_DIR="$OPTARG" ;;
            m)  MODE="$OPTARG" ;;
            v)  VERBOSE=1 ;;
            h)  usage; exit 0 ;;
            :)  die "Option -$OPTARG requires an argument" ;;
            \?) die "Unknown option: -$OPTARG" ;;
        esac
    done
    shift $(( OPTIND - 1 ))
    THEME_NAME="${1:-My Generated Theme}"
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    require_cmd jq node npm

    log "ThemePreview v${VERSION} — mode=${MODE} name='${THEME_NAME}'"

    local slug
    slug="$(slugify "$THEME_NAME")"
    local out_dir="${OUTPUT_DIR}/${slug}"
    mkdir -p "${out_dir}/themes"

    # Default palette if none given
    if (( ${#PALETTE[@]} == 0 )); then
        PALETTE=("#070425" "#14113d" "#9900FF" "#FF068B" "#09FBD3" "#5CB800")
    fi

    validate_palette PALETTE 2 || die "Palette validation failed"
    sort_by_lightness PALETTE

    local bg="${PALETTE[0]}"
    log "Background colour: $bg"

    # Generate package.json
    generate_package_json "$THEME_NAME" "$slug" "$bg" > "${out_dir}/package.json"
    log "Wrote ${out_dir}/package.json"

    # Print community archive
    printf '\n%s%-20s %-10s %-10s%s\n' "$BOLD" "Theme" "Background" "Keywords" "$RESET"
    printf '%-20s %-10s %-10s\n' "─────────────────" "──────────" "──────────"
    for theme_id in "${!COMMUNITY_THEMES[@]}"; do
        printf '%-20s %s%-10s%s %s%-10s%s\n' \
            "$theme_id" \
            "$CYAN"  "${COMMUNITY_THEMES[$theme_id]}"  "$RESET" \
            "$GREEN" "${THEME_KEYWORDS[$theme_id]:-N/A}" "$RESET"
    done | sort

    printf '\n%sDone! Extension scaffold written to: %s%s\n' "$GREEN" "$out_dir" "$RESET"
}

main "$@"
