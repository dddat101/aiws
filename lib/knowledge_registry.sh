#!/usr/bin/env bash
# lib/knowledge_registry.sh - Internal Seam: Knowledge state machine, auto-drift healer & staleness engine
set -Eeuo pipefail

# Register a domain in the Tier-1 index if not already present
registry_register_domain() {
    local domain_name="$1"
    local valid_paths_str="$2"
    local rel_out_file="$3"
    local custom_keywords="${4:-}"

    local desc="${custom_keywords:-Module under \`${valid_paths_str}\`}"

    if [[ -f "${INDEX_FILE}" ]] && ! grep -Fq "${rel_out_file}" "${INDEX_FILE}"; then
        printf "| \`%s\` | %s | \`%s\` | \`[SKELETON]\` |\n" \
            "${domain_name}" "${desc}" "${rel_out_file}" >> "${INDEX_FILE}"
    fi
}

# Refresh symbol line coordinates across one or more domain markdown files using current source definitions
registry_refresh_coords() {
    local target_domain="${1:-}"
    if [[ ! -d "${DOMAINS_DIR}" ]]; then
        return 0
    fi

    local -a md_files=()
    if [[ -n "${target_domain}" && -f "${DOMAINS_DIR}/${target_domain}.md" ]]; then
        md_files+=("${DOMAINS_DIR}/${target_domain}.md")
    else
        mapfile -t md_files < <(find "${DOMAINS_DIR}" -type f -name "*.md" ! -name "_template.md" | sort)
    fi

    [[ ${#md_files[@]} -eq 0 ]] && return 0

    local tmp_map
    tmp_map="$(mktemp)"
    local -a modified_md_files=()

    for md_file in "${md_files[@]}"; do
        [[ ! -f "${md_file}" ]] && continue
        # Extract referenced source files inside (`path/to/file:line`)
        local -a ref_files=()
        mapfile -t ref_files < <(grep -oE '\(`[a-zA-Z0-9_./-]+:[0-9]+`\)' "${md_file}" 2>/dev/null | sed -E 's/\(`([^:]+):[0-9]+`\)/\1/' | sort -u || true)
        [[ ${#ref_files[@]} -eq 0 ]] && continue

        : > "${tmp_map}"
        (cd -- "${CODEBASE_ROOT}" && build_symbol_line_map "${tmp_map}" "${ref_files[@]}")
        [[ ! -s "${tmp_map}" ]] && continue

        local tmp_md="${tmp_map}.md"
        awk -v map_file="${tmp_map}" '
            BEGIN {
                while ((getline line < map_file) > 0) {
                    n = split(line, parts, "|")
                    if (n == 3) {
                        coord[parts[1], parts[2]] = parts[3]
                    }
                }
                close(map_file)
            }
            {
                # Match any line containing `symbol` ... (`file:line`)
                if (match($0, /\(`[a-zA-Z0-9_./-]+:[0-9]+`\)/)) {
                    fcoord = substr($0, RSTART + 2, RLENGTH - 4)
                    colon_idx = index(fcoord, ":")
                    fpath = substr(fcoord, 1, colon_idx - 1)
                    old_lnum = substr(fcoord, colon_idx + 1)
                    prefix = substr($0, 1, RSTART - 1)
                    sym = ""
                    while (match(prefix, /`[^`]+`/)) {
                        cand = substr(prefix, RSTART + 1, RLENGTH - 2)
                        prefix = substr(prefix, RSTART + RLENGTH)
                        if (cand !~ /^\[/) {
                            sym = cand
                        }
                    }
                    if (sym != "") {
                        sub(/^(struct\/type|struct|class|def|export|declare)[[:space:]]+/, "", sym)
                        sub(/\(\)$/, "", sym)
                        sub(/^@/, "", sym)
                        new_lnum = coord[fpath, sym]
                        if (new_lnum != "" && new_lnum != old_lnum) {
                            sub("\\(`" fpath ":" old_lnum "`\\)", "(`" fpath ":" new_lnum "`)", $0)
                        }
                    }
                }
                print $0
            }
        ' "${md_file}" > "${tmp_md}"

        if ! cmp -s "${md_file}" "${tmp_md}"; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY-RUN] Would auto-refresh drifted line coordinates in ${md_file}"
            else
                cat "${tmp_md}" > "${md_file}"
            fi
            modified_md_files+=("${md_file}")
        fi
        rm -f "${tmp_md}"
    done

    rm -f "${tmp_map}"
    if [[ ${#modified_md_files[@]} -gt 0 && "${DRY_RUN}" == "false" ]]; then
        registry_commit_changes "Auto-refresh: Updated symbol line coordinates in ${#modified_md_files[@]} domain(s)" "${modified_md_files[@]}"
    fi
    printf "%d\n" "${#modified_md_files[@]}"
}

# Precision staleness invalidation:
# 1. Matches full relative paths or domain source prefixes (eliminates basename collision false positives)
# 2. Extracts modified function/struct names from git diff hunks for function-level invalidation
# 3. Auto-refreshes shifted line numbers in affected domains
registry_mark_stale() {
    local diff_mode="$1"
    shift
    local -a changed_src_files=("$@")
    local modified_domains=0
    local today
    today="$(date +%Y-%m-%d)"

    if [[ ! -d "${DOMAINS_DIR}" || ${#changed_src_files[@]} -eq 0 ]]; then
        printf "0\n"
        return 0
    fi

    # Pre-collect all domain markdown files once (avoids O(N*M) repeated find calls)
    local -a all_domain_files=()
    mapfile -t all_domain_files < <(find "${DOMAINS_DIR}" -type f -name "*.md" ! -name "_template.md" | sort)
    if [[ ${#all_domain_files[@]} -eq 0 ]]; then
        printf "0\n"
        return 0
    fi

    local recently_updated=""
    if [[ -d "${EXTERNAL_BASE}/.git" ]]; then
        recently_updated="$(git -C "${EXTERNAL_BASE}" status --porcelain 2>/dev/null | awk '{print $2}' || true)"
    fi

    local tmp_sym_map
    tmp_sym_map="$(mktemp)"
    (cd -- "${CODEBASE_ROOT}" && build_symbol_line_map "${tmp_sym_map}" "${changed_src_files[@]}")
    local -a touched_files=()

    for src_file in "${changed_src_files[@]}"; do
        [[ -z "${src_file}" ]] && continue
        local src_basename escaped_file escaped_base
        src_basename="$(basename -- "${src_file}")"
        escaped_file="$(escape_regex "${src_file}")"
        escaped_base="$(escape_regex "${src_basename}")"

        # Extract modified function/struct identifiers from git diff hunk headers (@@ ... @@ context)
        local -a modified_syms=()
        if command -v git >/dev/null 2>&1; then
            local diff_output=""
            if [[ "${diff_mode}" == "--cached" ]]; then
                diff_output="$(git -C "${CODEBASE_ROOT}" diff --cached -U0 -- "${src_file}" 2>/dev/null || true)"
            else
                diff_output="$(git -C "${CODEBASE_ROOT}" diff "${diff_mode}" -U0 -- "${src_file}" 2>/dev/null || true)"
            fi
            if [[ -n "${diff_output}" ]]; then
                mapfile -t modified_syms < <(printf "%s\n" "${diff_output}" | awk '
                    /^@@/ {
                        ctx = $0
                        sub(/^@@[^@]+@@[[:space:]]*/, "", ctx)
                        sub(/[[:space:]]*\(.*/, "", ctx)
                        n = split(ctx, parts, /[[:space:]*:]+/)
                        sym = parts[n]
                        if (sym != "" && sym ~ /^[a-zA-Z_][a-zA-Z0-9_]*$/) print sym
                    }
                    /^[+-][[:space:]]*(typedef[[:space:]]+)?(struct|class|def|function)[[:space:]]+[a-zA-Z0-9_]+/ {
                        line = $0
                        sub(/^[+-][[:space:]]*(typedef[[:space:]]+)?(struct|class|def|function)[[:space:]]+/, "", line)
                        sub(/[^a-zA-Z0-9_].*/, "", line)
                        if (line != "") print line
                    }
                ' | sort -u || true)
            fi
        fi

        for md_file in "${all_domain_files[@]}"; do
            [[ -z "${md_file}" || ! -f "${md_file}" ]] && continue
            local rel_md_path=".ai${md_file#"${AI_DIR}"}"

            # Skip files already dirty in the external AI git
            if printf "%s\n" "${recently_updated}" | grep -Fqx "${rel_md_path}"; then
                continue
            fi

            # Precision Path Matching:
            # Match exact relative path (`src_file`), OR match `src_basename` ONLY if `src_file` falls under the domain's Source paths
            local domain_matches=false
            if grep -Fq "${src_file}" "${md_file}"; then
                domain_matches=true
            elif grep -Fq "${src_basename}" "${md_file}"; then
                local domain_src_paths
                domain_src_paths="$(awk '
                    /^\*\*Source paths:\*\*/ {
                        in_paths = 1
                        line = $0
                        sub(/^\*\*Source paths:\*\*[[:space:]]*/, "", line)
                        gsub(/[,`]/, " ", line)
                        if (line !~ /^[[:space:]]*$/) print line
                        next
                    }
                    in_paths {
                        if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
                            line = $0
                            sub(/^[[:space:]]*-[[:space:]]+/, "", line)
                            gsub(/[,`]/, " ", line)
                            print line
                        } else if ($0 !~ /^[[:space:]]*$/) {
                            in_paths = 0
                        }
                    }
                ' "${md_file}" | tr '\n' ' ' || true)"
                for dp in ${domain_src_paths}; do
                    dp="${dp%/}"
                    if [[ "${src_file}" == "${dp}" || "${src_file}" == "${dp}/"* ]]; then
                        domain_matches=true
                        break
                    fi
                done
            fi

            [[ "${domain_matches}" == "false" ]] && continue

            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY-RUN] Would mark domain '${rel_md_path}' as [NEEDS_REVERIFY] due to '${src_file}'"
                modified_domains=$((modified_domains + 1))
                continue
            fi

            # Auto-heal drifted line coordinates in this domain file for unchanged symbols
            if [[ -s "${tmp_sym_map}" ]]; then
                local tmp_md="${tmp_sym_map}.md"
                awk -v map_file="${tmp_sym_map}" '
                    BEGIN {
                        while ((getline line < map_file) > 0) {
                            n = split(line, parts, "|")
                            if (n == 3) coord[parts[1], parts[2]] = parts[3]
                        }
                        close(map_file)
                    }
                    {
                        if (match($0, /\(`[a-zA-Z0-9_./-]+:[0-9]+`\)/)) {
                            fcoord = substr($0, RSTART + 2, RLENGTH - 4)
                            colon_idx = index(fcoord, ":")
                            fpath = substr(fcoord, 1, colon_idx - 1)
                            old_lnum = substr(fcoord, colon_idx + 1)
                            prefix = substr($0, 1, RSTART - 1)
                            sym = ""
                            while (match(prefix, /`[^`]+`/)) {
                                cand = substr(prefix, RSTART + 1, RLENGTH - 2)
                                prefix = substr(prefix, RSTART + RLENGTH)
                                if (cand !~ /^\[/) {
                                    sym = cand
                                }
                            }
                            if (sym != "") {
                                sub(/^(struct\/type|struct|class|def|export|declare)[[:space:]]+/, "", sym)
                                sub(/\(\)$/, "", sym)
                                sub(/^@/, "", sym)
                                new_lnum = coord[fpath, sym]
                                if (new_lnum != "" && new_lnum != old_lnum) {
                                    sub("\\(`" fpath ":" old_lnum "`\\)", "(`" fpath ":" new_lnum "`)", $0)
                                }
                            }
                        }
                        print $0
                    }
                ' "${md_file}" > "${tmp_md}" && cat "${tmp_md}" > "${md_file}"
                rm -f "${tmp_md}"
            fi

            # Function-level invalidation: if specific modified symbols were detected and referenced in flows, mark only those flows;
            # otherwise fall back to file-level flow invalidation
            local marked_specific=false
            if [[ ${#modified_syms[@]} -gt 0 ]]; then
                for msym in "${modified_syms[@]}"; do
                    [[ -z "${msym}" ]] && continue
                    local esc_sym
                    esc_sym="$(escape_regex "${msym}")"
                    if grep -Eq "\[([[:space:]]*VERIFIED|STATIC)[^]]*\].*\\b${esc_sym}\\b" "${md_file}"; then
                        sed --follow-symlinks -i -E "/\\b${esc_sym}\\b/ s/\[(VERIFIED|STATIC)([^]]*)\]/[NEEDS_REVERIFY]/g" "${md_file}"
                        marked_specific=true
                    fi
                done
            fi

            if [[ "${marked_specific}" == "false" ]]; then
                sed --follow-symlinks -i -E "/(${escaped_file}|${escaped_base})/ s/\[(VERIFIED|STATIC)([^]]*)\]/[NEEDS_REVERIFY]/g" "${md_file}"
            fi

            local sym_note=""
            if [[ ${#modified_syms[@]} -gt 0 ]]; then
                sym_note=" (modified symbols: \`${modified_syms[*]}\`)"
            fi

            if ! grep -Fq "> [!WARNING] [NEEDS_REVERIFY]" "${md_file}"; then
                sed --follow-symlinks -i "1a\\
\\
> [!WARNING] [NEEDS_REVERIFY]\\
> Associated source file (\`${src_file}\`)${sym_note} was modified on ${today}. Verify implementation details against actual source code." "${md_file}"
            fi

            if [[ -f "${INDEX_FILE}" ]] && grep -Fq "${rel_md_path}" "${INDEX_FILE}"; then
                sed --follow-symlinks -i -E "\|${rel_md_path}| s/\[(VERIFIED|STATIC)\]/[NEEDS_REVERIFY]/g" "${INDEX_FILE}"
                touched_files+=("${INDEX_FILE}")
            fi
            touched_files+=("${md_file}")
            modified_domains=$((modified_domains + 1))
        done
    done

    rm -f "${tmp_sym_map}"
    if [[ "${modified_domains}" -gt 0 && "${DRY_RUN}" == "false" ]]; then
        local src_branch
        src_branch="$(git -C "${CODEBASE_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'main')"
        registry_commit_changes "Auto-sync: Marked ${modified_domains} domain(s) on branch '${src_branch}' (${today})" "${touched_files[@]}"
    fi
    printf "%d\n" "${modified_domains}"
}

# Print status summary table of all registered knowledge domains
registry_print_status() {
    log_info "AI Workspace Status for: ${PROJECT_NAME}"
    log_info "External storage: ${EXTERNAL_BASE}"

    if [[ ! -f "${INDEX_FILE}" ]]; then
        log_warn "Knowledge index does not exist at ${INDEX_FILE}"
        return 0
    fi

    local verified_cnt=0
    local static_cnt=0
    local stale_cnt=0
    local skeleton_cnt=0
    local other_cnt=0
    local -a stale_domains=()
    local -a skeleton_domains=()

    printf "\n%-30s %-15s %s\n" "Domain / Module" "Status" "Knowledge File"
    printf "%-30s %-15s %s\n" "------------------------------" "---------------" "------------------------------"

    while IFS='|' read -r empty_col domain keywords kfile status rest; do
        [[ -z "${domain}" || "${domain}" =~ ^[[:space:]]*Domain || "${domain}" =~ ^[[:space:]]*:-- ]] && continue
        local clean_domain clean_status clean_file
        clean_domain="$(echo "${domain}" | tr -d '` ')"
        clean_status="$(echo "${status}" | tr -d '` ')"
        clean_file="$(echo "${kfile}" | tr -d '` ')"

        [[ "${clean_domain}" == "template_example" ]] && continue

        case "${clean_status}" in
            *VERIFIED*)       verified_cnt=$((verified_cnt + 1)) ;;
            *STATIC*)         static_cnt=$((static_cnt + 1)) ;;
            *NEEDS_REVERIFY*)
                stale_cnt=$((stale_cnt + 1))
                stale_domains+=("${clean_domain}")
                ;;
            *SKELETON*)
                skeleton_cnt=$((skeleton_cnt + 1))
                skeleton_domains+=("${clean_domain}")
                ;;
            *)                other_cnt=$((other_cnt + 1)) ;;
        esac

        printf "%-30s %-15s %s\n" "${clean_domain}" "${clean_status}" "${clean_file}"
    done < "${INDEX_FILE}"

    printf "\nSummary: %d Verified | %d Static | %d Needs Reverify | %d Skeleton | %d Other\n" \
        "${verified_cnt}" "${static_cnt}" "${stale_cnt}" "${skeleton_cnt}" "${other_cnt}"

    # Contextual Next-Step & Copy-Pasteable Prompt Suggestions (printed only when actionable items exist)
    if [[ ${#stale_domains[@]} -gt 0 || ${#skeleton_domains[@]} -gt 0 ]]; then
        printf "\nSuggested Next Steps & Prompts:\n"
        for sdom in "${stale_domains[@]:0:3}"; do
            local smd="${DOMAINS_DIR}/${sdom}.md"
            local mod_hint=""
            if [[ -f "${smd}" ]]; then
                mod_hint="$(grep -m1 "modified symbols:" "${smd}" | sed -E 's/.*(\(modified symbols: `[^`]+`\).*).*/ \1/' | sed -E 's/\).*//' || true)"
                [[ -n "${mod_hint}" ]] && mod_hint="${mod_hint})"
            fi
            printf -- "  [NEEDS_REVERIFY] %s%s:\n" "${sdom}" "${mod_hint}"
            printf -- "    Prompt: \"Reverify [NEEDS_REVERIFY] claims in .ai/domains/%s.md against git diff, update execution flows, and restore status.\"\n" "${sdom}"
        done
        for kdom in "${skeleton_domains[@]:0:3}"; do
            printf -- "  [SKELETON] %s:\n" "${kdom}"
            printf -- "    Prompt: \"Complete knowledge for %s in .ai/domains/%s.md using './.ai/ai-workspace slice', trace core execution flows, and promote to [STATIC].\"\n" "${kdom}" "${kdom}"
        done
    fi
}

# Reindex and reconcile index.md with all physical domain files in .ai/domains/
registry_reindex() {
    log_info "Reindexing knowledge registry for: ${PROJECT_NAME}"

    if [[ ! -d "${DOMAINS_DIR}" ]]; then
        log_warn "Domains directory does not exist at ${DOMAINS_DIR}"
        return 0
    fi

    local index_changed=false
    local added_count=0
    local updated_count=0

    # Ensure INDEX_FILE exists with base structure
    if [[ ! -f "${INDEX_FILE}" ]]; then
        log_info "Creating initial routing index at ${INDEX_FILE}"
        if [[ "${DRY_RUN}" == "false" ]]; then
            printf "%s\n" \
                "# Codebase Knowledge Routing Table (Tier 1)" \
                "" \
                "> **Agent Instruction:** Read this table FIRST before searching the source code. Only load the specific domain markdown file needed." \
                "" \
                "| Domain / Module | Keywords & Symptoms | Knowledge File | Status |" \
                "| :--- | :--- | :--- | :--- |" \
                "| \`template_example\` | Reference sample and structure for domain knowledge | \`.ai/domains/_template.md\` | \`[TEMPLATE]\` |" \
                > "${INDEX_FILE}"
            index_changed=true
        fi
    fi

    # Read all physical domain files
    while IFS= read -r md_file; do
        [[ -z "${md_file}" || ! -f "${md_file}" ]] && continue

        local rel_domain_path="${md_file#"${DOMAINS_DIR}/"}"
        local domain_name="${rel_domain_path%.md}"
        local rel_kfile=".ai/domains/${rel_domain_path}"
        local escaped_kfile
        escaped_kfile="$(escape_regex "${rel_kfile}")"

        # Determine actual status from file (supports both "**Overall Status:**" and legacy "**Status:**")
        local status="[SKELETON]"
        local overall_line
        overall_line="$(grep -Ei "^\*\*(Overall )?Status:\*\*" "${md_file}" | head -n 1 || true)"
        if grep -Fq "> [!WARNING] [NEEDS_REVERIFY]" "${md_file}"; then
            status="[NEEDS_REVERIFY]"
        elif [[ "${overall_line}" == *"[VERIFIED]"* && "${overall_line}" != *"[SKELETON"* ]]; then
            status="[VERIFIED]"
        elif [[ "${overall_line}" == *"[NEEDS_REVERIFY]"* ]]; then
            status="[NEEDS_REVERIFY]"
        elif [[ "${overall_line}" == *"[STATIC"* ]]; then
            status="[STATIC]"
        elif [[ "${overall_line}" == *"[SKELETON"* ]]; then
            status="[SKELETON]"
        fi

        # Extract source paths if available
        local src_paths
        src_paths="$(grep -m1 "^\*\*Source paths:\*\*" "${md_file}" | sed -E 's/\*\*Source paths:\*\* `?([^`]+)`?/\1/' || true)"
        [[ -z "${src_paths}" ]] && src_paths="Domain module ${domain_name}"

        if grep -Fq "${rel_kfile}" "${INDEX_FILE}"; then
            # Entry exists; check if status in index matches actual status
            local current_row
            current_row="$(grep -F "${rel_kfile}" "${INDEX_FILE}" || true)"
            if ! printf "%s\n" "${current_row}" | grep -Fq "${status}"; then
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_info "[DRY-RUN] Would update '${domain_name}' status to ${status} in ${INDEX_FILE}"
                else
                    sed --follow-symlinks -i -E "\|${escaped_kfile}| s/\[(VERIFIED|STATIC|NEEDS_REVERIFY|SKELETON|UNVERIFIED)[^]]*\]/${status}/" "${INDEX_FILE}"
                fi
                updated_count=$((updated_count + 1))
                index_changed=true
            fi
        else
            # Entry missing; append
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY-RUN] Would append missing domain '${domain_name}' (${status}) to ${INDEX_FILE}"
            else
                printf "| \`%s\` | Module under \`%s\` | \`%s\` | \`%s\` |\n" \
                    "${domain_name}" "${src_paths}" "${rel_kfile}" "${status}" >> "${INDEX_FILE}"
            fi
            added_count=$((added_count + 1))
            index_changed=true
        fi
    done < <(find "${DOMAINS_DIR}" -type f -name "*.md" ! -name "_template.md" | sort)

    # Ensure conventions entry exists if conventions.md is present
    if [[ -f "${AI_DIR}/conventions.md" ]] && ! grep -Fq ".ai/conventions.md" "${INDEX_FILE}"; then
        if [[ "${DRY_RUN}" == "false" ]]; then
            printf "| \`conventions\` | Project coding standards, memory ownership & locking conventions | \`.ai/conventions.md\` | \`[ACTIVE]\` |\n" >> "${INDEX_FILE}"
            index_changed=true
        fi
    fi

    # Check for orphaned entries in INDEX_FILE
    if [[ -f "${INDEX_FILE}" ]]; then
        while IFS='|' read -r empty_col domain keywords kfile status rest; do
            [[ -z "${domain}" || "${domain}" =~ ^[[:space:]]*Domain || "${domain}" =~ ^[[:space:]]*:-- ]] && continue
            local clean_kfile clean_domain
            clean_domain="$(echo "${domain}" | tr -d '` ')"
            clean_kfile="$(echo "${kfile}" | tr -d '` ')"
            [[ "${clean_domain}" == "template_example" || "${clean_domain}" == "conventions" ]] && continue
            local physical_path="${AI_DIR}${clean_kfile#\.ai}"
            if [[ ! -f "${physical_path}" ]]; then
                log_warn "Orphaned entry in ${INDEX_FILE}: '${clean_domain}' (${clean_kfile}) not found on disk."
            fi
        done < "${INDEX_FILE}"
    fi

    if [[ "${index_changed}" == "true" && "${DRY_RUN}" == "false" ]]; then
        registry_commit_changes "Reindex: Synchronized index.md (+${added_count} added, ${updated_count} updated)" "${INDEX_FILE}"
        log_success "Knowledge index updated: +${added_count} added, ${updated_count} status updated."
    else
        log_info "Knowledge index is already up-to-date."
    fi
}

# Commit specified files (or all files if none specified) to the external Git repository
# Protects uncommitted colleague/agent WIP in other files when specific paths are provided
registry_commit_changes() {
    local message="$1"
    shift
    local -a target_files=("$@")
    if [[ "${DRY_RUN}" == "false" && -d "${EXTERNAL_BASE}/.git" ]] && command -v git >/dev/null 2>&1; then
        if ! git -C "${EXTERNAL_BASE}" config user.email >/dev/null 2>&1; then
            git -C "${EXTERNAL_BASE}" config user.email "ai-workspace@local"
            git -C "${EXTERNAL_BASE}" config user.name "AI Workspace"
        fi
        if [[ ${#target_files[@]} -gt 0 ]]; then
            git -C "${EXTERNAL_BASE}" add -- "${target_files[@]}" 2>/dev/null || true
        else
            git -C "${EXTERNAL_BASE}" add -A 2>/dev/null || true
        fi
        if ! git -C "${EXTERNAL_BASE}" diff --cached --quiet 2>/dev/null; then
            git -C "${EXTERNAL_BASE}" commit -q -m "${message}" || true
        fi
    fi
}
