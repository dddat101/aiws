#!/usr/bin/env bash
# lib/symbol_extractor.sh - Internal Seam: High-speed multi-language symbol extraction & slicing engine
# Supports: C/C++, Python, and Shell/Bash with token-economical pruning and surgical source slicing
set -Eeuo pipefail

# Default threshold for pruning internal/static symbols to save LLM context tokens
MAX_STATIC_SYMBOLS="${MAX_STATIC_SYMBOLS:-80}"

# Collect all matching source files (C/C++, Python, Shell) from specified paths
# Uses ripgrep (rg --files) when available for 10x-50x faster traversal
collect_source_files() {
    local -a search_paths=("$@")
    local -a dirs=()
    local -a files=()

    for p in "${search_paths[@]}"; do
        if [[ -d "$p" ]]; then
            dirs+=("$p")
        elif [[ -f "$p" ]]; then
            files+=("$p")
        fi
    done

    if [[ ${#files[@]} -gt 0 ]]; then
        printf "%s\n" "${files[@]}"
    fi

    if [[ ${#dirs[@]} -gt 0 ]]; then
        if command -v rg >/dev/null 2>&1; then
            rg --files \
                -g '*.c' -g '*.h' -g '*.cpp' -g '*.hpp' -g '*.cc' -g '*.cxx' \
                -g '*.py' -g '*.sh' -g '*.bash' \
                "${dirs[@]}" 2>/dev/null | sort -u || true
        else
            find "${dirs[@]}" -type f \( \
                -name "*.c" -o -name "*.h" -o -name "*.cpp" -o -name "*.hpp" -o -name "*.cc" -o -name "*.cxx" \
                -o -name "*.py" \
                -o -name "*.sh" -o -name "*.bash" \
            \) 2>/dev/null | sort -u || true
        fi
    fi
}

# Backward compatibility alias
collect_c_source_files() {
    collect_source_files "$@"
}

# Batch regex runner: runs ripgrep or grep across an array of files in a single process invocation
_batch_grep() {
    local pattern="$1"
    shift
    if [[ $# -eq 0 ]]; then
        return 0
    fi
    if command -v rg >/dev/null 2>&1; then
        rg --no-heading --with-filename --line-number --color=never -e "${pattern}" "$@" 2>/dev/null || true
    else
        grep -EnH "${pattern}" "$@" 2>/dev/null || true
    fi
}

# Main extraction interface: extracts structures/classes, public/test APIs, internal/static functions, and callbacks/fixtures/traps
extract_symbols() {
    local out_structs="$1"
    local out_pub_funcs="$2"
    local out_static_funcs="$3"
    local out_callbacks="$4"
    shift 4
    local -a target_paths=("$@")

    local -a src_files=()
    mapfile -t src_files < <(collect_source_files "${target_paths[@]}")

    if [[ ${#src_files[@]} -eq 0 ]]; then
        return 0
    fi

    # Classify files by language
    local -a c_files=()
    local -a py_files=()
    local -a sh_files=()

    for f in "${src_files[@]}"; do
        [[ -z "$f" || ! -f "$f" ]] && continue
        case "$f" in
            *.c|*.h|*.cpp|*.hpp|*.cc|*.cxx) c_files+=("$f") ;;
            *.py) py_files+=("$f") ;;
            *.sh|*.bash) sh_files+=("$f") ;;
            *)
                if head -n 1 "$f" 2>/dev/null | grep -Eq '^#!/(.*/)?(bash|sh)'; then
                    sh_files+=("$f")
                elif head -n 1 "$f" 2>/dev/null | grep -Eq '^#!/(.*/)?(python)'; then
                    py_files+=("$f")
                fi
                ;;
        esac
    done

    # -------------------------------------------------------------
    # 1. C / C++ Symbol Extraction (Single-Pass Ctags or Batch AWK/RG)
    # -------------------------------------------------------------
    if [[ ${#c_files[@]} -gt 0 ]]; then
        local has_ctags=false
        if command -v ctags >/dev/null 2>&1 && ctags --version 2>&1 | grep -qi "Universal Ctags"; then
            has_ctags=true
            # Single-pass Universal Ctags invocation for structs, typedefs, and functions
            ctags --languages=C,C++ --c-kinds=stf --fields=+S --extras=+f -x "${c_files[@]}" 2>/dev/null | \
                awk -v f_struct="${out_structs}" -v f_pub="${out_pub_funcs}" -v f_stat="${out_static_funcs}" '
                {
                    sym = $1
                    kind = $2
                    lnum = $3
                    file = $4
                    if (sym == file) next
                    if (kind == "struct" || kind == "typedef") {
                        printf "- `struct/type %s` (`%s:%s`)\n", sym, file, lnum >> f_struct
                    } else if (kind == "function") {
                        if ($0 ~ /\<static\>/) {
                            printf "- `%s()` (`%s:%s`) [static]\n", sym, file, lnum >> f_stat
                        } else {
                            printf "- `%s()` (`%s:%s`)\n", sym, file, lnum >> f_pub
                        }
                    }
                }' || true
        fi

        # High-speed batch fallback for C/C++ structs
        if [[ "${has_ctags}" == "false" || ! -s "${out_structs}" ]]; then
            _batch_grep '^\s*(typedef\s+)?struct\s+[a-zA-Z0-9_]+' "${c_files[@]}" | \
                awk -F: '{
                    file = $1
                    lnum = $2
                    line = substr($0, length(file) + length(lnum) + 3)
                    if (match(line, /struct[[:space:]]+[a-zA-Z0-9_]+/)) {
                        s = substr(line, RSTART, RLENGTH)
                        sub(/^struct[[:space:]]+/, "", s)
                        if (s != "") printf "- `struct %s` (`%s:%s`)\n", s, file, lnum
                    }
                }' >> "${out_structs}" || true
        fi

        # High-speed batch fallback for C/C++ functions (excludes trivial static inline header helpers)
        if [[ "${has_ctags}" == "false" || (! -s "${out_pub_funcs}" && ! -s "${out_static_funcs}") ]]; then
            _batch_grep '^\s*(static\s+)?[a-zA-Z0-9_]+(\s+\*|\s+)+[a-zA-Z0-9_]+\s*\([^;)]*\)\s*\{' "${c_files[@]}" | \
                awk -F: -v f_pub="${out_pub_funcs}" -v f_stat="${out_static_funcs}" '{
                    file = $1
                    lnum = $2
                    line = substr($0, length(file) + length(lnum) + 3)
                    if (line ~ /\<inline\>/ && file ~ /\.h(pp)?$/) next
                    is_static = (line ~ /^[[:space:]]*static\>/)
                    sub(/[[:space:]]*\([^;)]*\)[[:space:]]*\{?.*/, "", line)
                    n = split(line, parts, /[[:space:]*]+/)
                    fname = parts[n]
                    if (fname == "" || fname ~ /^(if|for|while|switch|return|sizeof)$/) next
                    if (is_static) {
                        printf "- `%s()` (`%s:%s`) [static]\n", fname, file, lnum >> f_stat
                    } else {
                        printf "- `%s()` (`%s:%s`)\n", fname, file, lnum >> f_pub
                    }
                }' || true
        fi

        # Batch C Callback function pointer discovery
        _batch_grep '\(\s*\*[a-zA-Z0-9_]+\s*\)\s*\(' "${c_files[@]}" | \
            awk -F: '{
                file = $1
                lnum = $2
                line = substr($0, length(file) + length(lnum) + 3)
                if (match(line, /\([[:space:]]*\*[a-zA-Z0-9_]+[[:space:]]*\)/)) {
                    cb = substr(line, RSTART, RLENGTH)
                    gsub(/[()*[:space:]]/, "", cb)
                    if (cb != "") printf "- `%s` callback pointer (`%s:%s`)\n", cb, file, lnum
                }
            }' >> "${out_callbacks}" || true
    fi

    # -------------------------------------------------------------
    # 2. Python Symbol Extraction (Batch Processing)
    # -------------------------------------------------------------
    if [[ ${#py_files[@]} -gt 0 ]]; then
        # Classes
        _batch_grep '^[[:space:]]*class[[:space:]]+[a-zA-Z0-9_]+' "${py_files[@]}" | \
            awk -F: '{
                file = $1; lnum = $2
                line = substr($0, length(file) + length(lnum) + 3)
                sub(/^[[:space:]]*class[[:space:]]+/, "", line)
                sub(/[[:space:]:].*/, "", line)
                if (line != "") printf "- `class %s` (`%s:%s`)\n", line, file, lnum
            }' >> "${out_structs}" || true

        # Functions & test cases
        _batch_grep '^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[a-zA-Z0-9_]+' "${py_files[@]}" | \
            awk -F: -v f_pub="${out_pub_funcs}" -v f_stat="${out_static_funcs}" '{
                file = $1; lnum = $2
                line = substr($0, length(file) + length(lnum) + 3)
                sub(/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+/, "", line)
                sub(/[[:space:](].*/, "", line)
                if (line == "") next
                if (line ~ /^_/) {
                    printf "- `def %s()` (`%s:%s`) [internal]\n", line, file, lnum >> f_stat
                } else if (line ~ /^test_/) {
                    printf "- `def %s()` (`%s:%s`) [test_case]\n", line, file, lnum >> f_pub
                } else {
                    printf "- `def %s()` (`%s:%s`)\n", line, file, lnum >> f_pub
                }
            }' || true

        # Decorators & fixtures
        _batch_grep '^[[:space:]]*@[a-zA-Z0-9_.]+' "${py_files[@]}" | \
            awk -F: '{
                file = $1; lnum = $2
                line = substr($0, length(file) + length(lnum) + 3)
                sub(/^[[:space:]]*@/, "", line)
                sub(/[^a-zA-Z0-9_.].*/, "", line)
                if (line != "") printf "- `@%s` decorator/fixture (`%s:%s`)\n", line, file, lnum
            }' >> "${out_callbacks}" || true
    fi

    # -------------------------------------------------------------
    # 3. Shell / Bash Symbol Extraction (Batch Processing)
    # -------------------------------------------------------------
    if [[ ${#sh_files[@]} -gt 0 ]]; then
        # Exported variables and declarations
        _batch_grep '^[[:space:]]*(export|declare)[[:space:]]+' "${sh_files[@]}" | \
            awk -F: '{
                file = $1; lnum = $2
                line = substr($0, length(file) + length(lnum) + 3)
                sub(/^[[:space:]]*/, "", line)
                sub(/[=;].*/, "", line)
                if (line != "") printf "- `%s` environment/global (`%s:%s`)\n", line, file, lnum
            }' >> "${out_structs}" || true

        # Shell functions
        _batch_grep '^[[:space:]]*(function[[:space:]]+[a-zA-Z0-9_]+|[a-zA-Z0-9_]+[[:space:]]*\(\))' "${sh_files[@]}" | \
            awk -F: -v f_pub="${out_pub_funcs}" -v f_stat="${out_static_funcs}" '{
                file = $1; lnum = $2
                line = substr($0, length(file) + length(lnum) + 3)
                sub(/^[[:space:]]*function[[:space:]]+/, "", line)
                sub(/[[:space:]]*\(.*/, "", line)
                sub(/[[:space:]]*\{.*/, "", line)
                sub(/^[[:space:]]+/, "", line)
                if (line == "") next
                if (line ~ /^_/) {
                    printf "- `%s()` (`%s:%s`) [helper]\n", line, file, lnum >> f_stat
                } else {
                    printf "- `%s()` (`%s:%s`)\n", line, file, lnum >> f_pub
                }
            }' || true

        # Signal traps & event hooks
        _batch_grep '^[[:space:]]*trap[[:space:]]+' "${sh_files[@]}" | \
            awk -F: '{
                file = $1; lnum = $2
                line = substr($0, length(file) + length(lnum) + 3)
                sub(/^[[:space:]]*/, "", line)
                sub(/;.*/, "", line)
                if (line != "") printf "- `%s` signal trap (`%s:%s`)\n", line, file, lnum
            }' >> "${out_callbacks}" || true
    fi

    # Sort and deduplicate all collected symbols
    sort -u -o "${out_structs}" "${out_structs}" 2>/dev/null || true
    sort -u -o "${out_pub_funcs}" "${out_pub_funcs}" 2>/dev/null || true
    sort -u -o "${out_static_funcs}" "${out_static_funcs}" 2>/dev/null || true
    sort -u -o "${out_callbacks}" "${out_callbacks}" 2>/dev/null || true

    # Token Economy Pruning: Cap excessive internal/static symbols
    if [[ -s "${out_static_funcs}" && "${MAX_STATIC_SYMBOLS}" -gt 0 ]]; then
        local total_static
        total_static="$(wc -l < "${out_static_funcs}" | tr -d ' ')"
        if [[ "${total_static}" -gt "${MAX_STATIC_SYMBOLS}" ]]; then
            local omitted=$((total_static - MAX_STATIC_SYMBOLS))
            local pruned_tmp="${out_static_funcs}.pruned"
            head -n "${MAX_STATIC_SYMBOLS}" "${out_static_funcs}" > "${pruned_tmp}"
            printf -- "- *(... %d additional internal/static symbols omitted for token economy; use \`ai-workspace slice <symbol>\` to inspect)*\n" "${omitted}" >> "${pruned_tmp}"
            mv "${pruned_tmp}" "${out_static_funcs}"
        fi
    fi

    # Default fallback notes if empty
    [[ ! -s "${out_structs}" ]] && printf -- "- *(No structs/classes/configs detected)*\n" > "${out_structs}"
    [[ ! -s "${out_pub_funcs}" ]] && printf -- "- *(No public/test functions detected)*\n" > "${out_pub_funcs}"
    [[ ! -s "${out_static_funcs}" ]] && printf -- "- *(No internal/helper functions detected)*\n" > "${out_static_funcs}"
    [[ ! -s "${out_callbacks}" ]] && printf -- "- *(No callbacks/fixtures/traps detected)*\n" > "${out_callbacks}"

    return 0
}

# Build a compact, high-signal routing summary (top structs, APIs, callbacks) for .ai/index.md
generate_domain_keywords() {
    local f_structs="$1"
    local f_pub="$2"
    local f_callbacks="$3"
    local valid_paths_str="$4"

    local top_syms=""
    top_syms="$(awk -F'`' '
        /^-[[:space:]]*`/ && $2 !~ /^\*\(/ {
            sym = $2
            sub(/^(struct\/type|struct|class|def|export|declare)[[:space:]]+/, "", sym)
            sub(/\(\)$/, "", sym)
            if (sym != "" && !seen[sym]++) {
                items[++count] = sym
                if (count >= 5) exit
            }
        }
        END {
            for (i = 1; i <= count; i++) {
                printf "%s%s", items[i], (i < count ? ", " : "")
            }
        }
    ' "${f_structs}" "${f_pub}" "${f_callbacks}" 2>/dev/null || true)"

    if [[ -n "${top_syms}" ]]; then
        printf "Paths: \`%s\` (Key symbols: \`%s\`)" "${valid_paths_str}" "${top_syms}"
    else
        printf "Module under \`%s\`" "${valid_paths_str}"
    fi
}

# Build a lookup table of "file|symbol|line" for a list of source files (used by auto coordinate drift healer)
build_symbol_line_map() {
    local out_map="$1"
    shift
    local -a target_files=("$@")
    [[ ${#target_files[@]} -eq 0 ]] && return 0

    local -a existing_files=()
    for f in "${target_files[@]}"; do
        [[ -f "$f" ]] && existing_files+=("$f")
    done
    [[ ${#existing_files[@]} -eq 0 ]] && return 0

    if command -v ctags >/dev/null 2>&1 && ctags --version 2>&1 | grep -qi "Universal Ctags"; then
        ctags -x "${existing_files[@]}" 2>/dev/null | awk '{
            if ($1 != $4) printf "%s|%s|%s\n", $4, $1, $3
        }' >> "${out_map}" || true
    fi

    # Supplement with batch regex scan for C, Python, and Shell definitions
    _batch_grep '^\s*((typedef\s+)?struct\s+[a-zA-Z0-9_]+|(static\s+)?[a-zA-Z0-9_]+(\s+\*|\s+)+[a-zA-Z0-9_]+\s*\([^;)]*\)\s*\{|class\s+[a-zA-Z0-9_]+|(async\s+)?def\s+[a-zA-Z0-9_]+|(function\s+[a-zA-Z0-9_]+|[a-zA-Z0-9_]+\s*\(\)))' "${existing_files[@]}" | \
        awk -F: '{
            file = $1; lnum = $2
            line = substr($0, length(file) + length(lnum) + 3)
            sym = ""
            if (line ~ /\(/) {
                sub(/[[:space:]]*\(.*/, "", line)
                sub(/^[[:space:]]*(async[[:space:]]+)?(def|function)[[:space:]]+/, "", line)
                n = split(line, parts, /[[:space:]*]+/)
                sym = parts[n]
            } else if (match(line, /struct[[:space:]]+[a-zA-Z0-9_]+/)) {
                sym = substr(line, RSTART, RLENGTH)
                sub(/^struct[[:space:]]+/, "", sym)
            } else if (match(line, /class[[:space:]]+[a-zA-Z0-9_]+/)) {
                sym = substr(line, RSTART, RLENGTH)
                sub(/^class[[:space:]]+/, "", sym)
            }
            if (sym != "" && sym !~ /^(if|for|while|switch|return|sizeof)$/) {
                printf "%s|%s|%s\n", file, sym, lnum
            }
        }' >> "${out_map}" || true

    sort -u -o "${out_map}" "${out_map}" 2>/dev/null || true
}

# Surgical Tier-3 Source Slicer: Extracts exact function/struct/class block with line numbers
slice_source_entity() {
    local query="$1"
    local max_lines="${2:-160}"
    local target_file=""
    local start_line=0
    local end_line=0

    # Case 1: Explicit coordinate file:start[-end] or file:line:symbol
    if [[ "${query}" =~ ^([^:]+):([0-9]+)(-([0-9]+))?$ ]]; then
        target_file="${BASH_REMATCH[1]}"
        start_line="${BASH_REMATCH[2]}"
        end_line="${BASH_REMATCH[4]:-0}"
    elif [[ "${query}" =~ ^([^:]+):([a-zA-Z0-9_]+)$ ]]; then
        target_file="${BASH_REMATCH[1]}"
        local sym_name="${BASH_REMATCH[2]}"
        if [[ -f "${target_file}" ]]; then
            start_line="$(_batch_grep "\\b${sym_name}\\b" "${target_file}" | head -n 1 | cut -d: -f2 || printf '0')"
        fi
    else
        # Case 2: Symbol name lookup -> check .ai/domains/*.md coordinates first!
        local sym_name="${query%()}"
        if [[ -d "${DOMAINS_DIR:-}" ]]; then
            local coord_match=""
            coord_match="$(_batch_grep "\`([a-zA-Z0-9_]+ )?${sym_name}(\(\))?\` \(\`[^\`]+:[0-9]+\`\)" "${DOMAINS_DIR}" | head -n 1 || true)"
            if [[ -n "${coord_match}" ]]; then
                local extracted_coord
                extracted_coord="$(printf "%s\n" "${coord_match}" | sed -E 's/.*\(`([^`]+:[0-9]+)`\).*/\1/')"
                target_file="${extracted_coord%%:*}"
                start_line="${extracted_coord##*:}"
            fi
        fi

        # Fallback: search codebase directly for definition
        if [[ -z "${target_file}" || ! -f "${target_file}" ]]; then
            local def_match=""
            if command -v rg >/dev/null 2>&1; then
                def_match="$(rg --no-heading --with-filename --line-number --color=never -m 1 \
                    -e "^[[:space:]]*((typedef[[:space:]]+)?struct[[:space:]]+${sym_name}\\b|(static[[:space:]]+)?[a-zA-Z0-9_*[:space:]]+\\b${sym_name}[[:space:]]*\\(|class[[:space:]]+${sym_name}\\b|(async[[:space:]]+)?def[[:space:]]+${sym_name}\\b|(function[[:space:]]+)?${sym_name}[[:space:]]*\\(\\))" \
                    "${CODEBASE_ROOT}" 2>/dev/null | head -n 1 || true)"
            else
                def_match="$(grep -rnE "^[[:space:]]*((typedef[[:space:]]+)?struct[[:space:]]+${sym_name}\b|(static[[:space:]]+)?[a-zA-Z0-9_*[:space:]]+\b${sym_name}[[:space:]]*\(|class[[:space:]]+${sym_name}\b|(async[[:space:]]+)?def[[:space:]]+${sym_name}\b|(function[[:space:]]+)?${sym_name}[[:space:]]*\(\))" \
                    "${CODEBASE_ROOT}" 2>/dev/null | head -n 1 || true)"
            fi
            if [[ -n "${def_match}" ]]; then
                target_file="$(printf "%s" "${def_match}" | cut -d: -f1)"
                start_line="$(printf "%s" "${def_match}" | cut -d: -f2)"
            fi
        fi
    fi

    if [[ -z "${target_file}" || ! -f "${target_file}" || "${start_line}" -le 0 ]]; then
        log_error "Could not resolve symbol or coordinate: '${query}'"
        return 1
    fi

    local rel_file="${target_file#"${CODEBASE_ROOT}/"}"
    printf "# Slice: %s (starting at line %d)\n" "${rel_file}" "${start_line}"

    # If explicit end_line was provided, print exact range
    if [[ "${end_line}" -gt "${start_line}" ]]; then
        awk -v s="${start_line}" -v e="${end_line}" 'NR >= s && NR <= e { printf "%5d: %s\n", NR, $0 }' "${target_file}"
        return 0
    fi

    # Smart language-aware block slicer (tracks brace depth for C/C++/Shell and indentation for Python)
    case "${target_file}" in
        *.py)
            awk -v s="${start_line}" -v max="${max_lines}" '
                NR < s { next }
                NR == s {
                    match($0, /^[[:space:]]*/)
                    base_indent = RLENGTH
                    printf "%5d: %s\n", NR, $0
                    count = 1
                    next
                }
                {
                    if ($0 !~ /^[[:space:]]*$/ && $0 !~ /^[[:space:]]*#/) {
                        match($0, /^[[:space:]]*/)
                        if (RLENGTH <= base_indent && $0 !~ /^[[:space:]]*(elif|else|except|finally)\b/) {
                            exit
                        }
                    }
                    printf "%5d: %s\n", NR, $0
                    if (++count >= max) {
                        printf "  ... [truncated after %d lines]\n", max
                        exit
                    }
                }
            ' "${target_file}"
            ;;
        *)
            awk -v s="${start_line}" -v max="${max_lines}" '
                NR < s { next }
                {
                    printf "%5d: %s\n", NR, $0
                    count++
                    line = $0
                    # Strip quoted strings and single-line comments before counting braces
                    gsub(/"([^"\\]|\\.)*"/, "", line)
                    gsub(/\x27([^\x27\\]|\\.)*\x27/, "", line)
                    sub(/\/\/.*/, "", line)
                    n_open = gsub(/\{/, "{", line)
                    n_close = gsub(/\}/, "}", line)
                    if (n_open > 0) seen_open = 1
                    depth += (n_open - n_close)
                    if (seen_open && depth <= 0) {
                        exit
                    }
                    if (!seen_open && count <= 5 && line ~ /;[[:space:]]*$/) {
                        exit
                    }
                    if (count >= max) {
                        printf "  ... [truncated after %d lines]\n", max
                        exit
                    }
                }
            ' "${target_file}"
            ;;
    esac
}
