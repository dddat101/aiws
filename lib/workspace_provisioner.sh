#!/usr/bin/env bash
# lib/workspace_provisioner.sh - Internal Seam: Workspace provisioning & dual-repo management
set -Eeuo pipefail

provision_workspace() {
    local source_root="$1"

    log_info "Target codebase root: ${CODEBASE_ROOT}"
    log_info "Target external storage: ${EXTERNAL_BASE}"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "Running in DRY-RUN mode. No changes will be applied."
    fi

    # 1. Create external directories
    run_cmd mkdir -p "${EXTERNAL_BASE}/.ai/domains"
    run_cmd mkdir -p "${EXTERNAL_BASE}/.ai/scripts"
    run_cmd mkdir -p "${EXTERNAL_BASE}/.ai/lib"

    # Clean up legacy .agent or .agents in external storage if present
    if [[ -d "${EXTERNAL_BASE}/.agent" || -L "${EXTERNAL_BASE}/.agent" ]]; then
        run_cmd rm -rf "${EXTERNAL_BASE}/.agent"
    fi
    if [[ -d "${EXTERNAL_BASE}/.agents" || -L "${EXTERNAL_BASE}/.agents" ]]; then
        run_cmd rm -rf "${EXTERNAL_BASE}/.agents"
    fi

    # 2. Initialize independent Git repository
    if command -v git >/dev/null 2>&1 && [[ ! -d "${EXTERNAL_BASE}/.git" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would initialize Git repository at ${EXTERNAL_BASE}"
        else
            git -C "${EXTERNAL_BASE}" init -q
            if ! git -C "${EXTERNAL_BASE}" config user.email >/dev/null 2>&1; then
                git -C "${EXTERNAL_BASE}" config user.email "ai-workspace@local"
                git -C "${EXTERNAL_BASE}" config user.name "AI Workspace"
            fi
            log_info "Initialized independent Git repository at ${EXTERNAL_BASE}"
        fi
    fi

    # 3. Deploy routing table
    if [[ ! -f "${INDEX_FILE}" ]]; then
        if [[ -f "${source_root}/templates/index.md" ]]; then
            run_cmd cp "${source_root}/templates/index.md" "${INDEX_FILE}"
            log_info "Deployed routing table to ${INDEX_FILE}"
        else
            run_cmd printf "# Codebase Knowledge Routing Table (Tier 1)\n\n> **Agent Instruction:** Read this table FIRST before searching the source code. Only load the specific domain markdown file needed.\n\n| Domain / Module | Keywords & Symptoms | Knowledge File | Status |\n| :--- | :--- | :--- | :--- |\n| \`template_example\` | Reference sample and structure for domain knowledge | \`.ai/domains/_template.md\` | \`[TEMPLATE]\` |\n| \`conventions\` | Project coding standards, memory ownership & locking conventions | \`.ai/conventions.md\` | \`[ACTIVE]\` |\n" > "${INDEX_FILE}"
        fi
    fi

    # Deploy lessons learned
    if [[ ! -f "${LESSONS_FILE}" ]]; then
        if [[ -f "${source_root}/templates/lessons_learned.md" ]]; then
            run_cmd cp "${source_root}/templates/lessons_learned.md" "${LESSONS_FILE}"
            log_info "Deployed lessons learned template to ${LESSONS_FILE}"
        else
            run_cmd printf "# Runtime Lessons Learned & Anti-Patterns\n\nThis document tracks discrepancies discovered between static code analysis and actual runtime behavior, debugging traps, and unexpected edge cases.\n" > "${LESSONS_FILE}"
        fi
    fi

    # Deploy conventions
    if [[ ! -f "${CONVENTIONS_FILE}" ]]; then
        if [[ -f "${source_root}/templates/conventions.md" ]]; then
            run_cmd cp "${source_root}/templates/conventions.md" "${CONVENTIONS_FILE}"
            log_info "Deployed conventions template to ${CONVENTIONS_FILE}"
        fi
    fi

    # Deploy default domain template
    if [[ ! -f "${EXTERNAL_BASE}/.ai/domains/_template.md" ]]; then
        if [[ -f "${source_root}/templates/_template.md" ]]; then
            run_cmd cp "${source_root}/templates/_template.md" "${EXTERNAL_BASE}/.ai/domains/_template.md"
            log_info "Deployed domain template to ${EXTERNAL_BASE}/.ai/domains/_template.md"
        fi
    fi

    # 4. Deploy AGENTS.md
    if [[ ! -f "${EXTERNAL_BASE}/AGENTS.md" ]]; then
        if [[ -f "${source_root}/AGENTS.md" && "${source_root}/AGENTS.md" != "${EXTERNAL_BASE}/AGENTS.md" ]]; then
            run_cmd cp "${source_root}/AGENTS.md" "${EXTERNAL_BASE}/AGENTS.md"
            log_info "Deployed standard AGENTS.md to external workspace."
        elif [[ -f "${CODEBASE_ROOT}/AGENTS.md" && ! -L "${CODEBASE_ROOT}/AGENTS.md" ]]; then
            run_cmd cp "${CODEBASE_ROOT}/AGENTS.md" "${EXTERNAL_BASE}/AGENTS.md"
            log_info "Migrated codebase AGENTS.md to external workspace."
        fi
    fi

    # 5. Deploy scripts, libs, and master binary into external workspace
    if [[ -d "${source_root}/scripts" && "${source_root}/scripts" != "${EXTERNAL_BASE}/.ai/scripts" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would copy scripts to ${EXTERNAL_BASE}/.ai/scripts/"
        else
            cp -r "${source_root}/scripts/"* "${EXTERNAL_BASE}/.ai/scripts/" 2>/dev/null || true
            chmod +x "${EXTERNAL_BASE}/.ai/scripts/"*.sh 2>/dev/null || true
            log_info "Copied scripts to ${EXTERNAL_BASE}/.ai/scripts/"
        fi
    fi

    if [[ -d "${source_root}/lib" && "${source_root}/lib" != "${EXTERNAL_BASE}/.ai/lib" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would copy lib modules to ${EXTERNAL_BASE}/.ai/lib/"
        else
            cp -r "${source_root}/lib/"* "${EXTERNAL_BASE}/.ai/lib/" 2>/dev/null || true
            log_info "Copied lib modules to ${EXTERNAL_BASE}/.ai/lib/"
        fi
    fi

    if [[ -f "${source_root}/ai-workspace" && "${source_root}/ai-workspace" != "${EXTERNAL_BASE}/.ai/ai-workspace" ]]; then
        run_cmd cp "${source_root}/ai-workspace" "${EXTERNAL_BASE}/.ai/ai-workspace"
        [[ "${DRY_RUN}" == "false" ]] && chmod +x "${EXTERNAL_BASE}/.ai/ai-workspace"
    fi

    # 6. Deploy agent skills to ~/.agents/skills and CLI binary to ~/.local/bin (Global Scope)
    local global_skills_dir="${HOME}/.agents/skills"
    run_cmd mkdir -p "${global_skills_dir}"

    if [[ -d "${source_root}/skills" ]]; then
        for skill_path in "${source_root}/skills/"*; do
            if [[ -d "${skill_path}" ]]; then
                local skill_name
                skill_name="$(basename -- "${skill_path}")"
                local skill_target="${global_skills_dir}/${skill_name}"
                run_cmd ln -sfn "${skill_path}" "${skill_target}"
                log_info "Linked skill '${skill_name}' to ${skill_target}"
            fi
        done
    fi

    if [[ -f "${source_root}/ai-workspace" ]]; then
        local global_bin_dir="${HOME}/.local/bin"
        run_cmd mkdir -p "${global_bin_dir}"
        run_cmd ln -sfn "${source_root}/ai-workspace" "${global_bin_dir}/ai-workspace"
        log_info "Linked global CLI binary to ${global_bin_dir}/ai-workspace"
    fi

    # Initial commit in external Git
    if command -v git >/dev/null 2>&1 && [[ -d "${EXTERNAL_BASE}/.git" && "${DRY_RUN}" == "false" ]]; then
        git -C "${EXTERNAL_BASE}" add -A
        git -C "${EXTERNAL_BASE}" commit -q -m "Initial workspace setup for ${PROJECT_NAME}" || true
    fi

    # 7. Symlink external workspace into codebase
    for item in ".ai" "AGENTS.md"; do
        local target="${CODEBASE_ROOT}/${item}"
        local source="${EXTERNAL_BASE}/${item}"

        if [[ -e "${target}" && ! -L "${target}" && "${target}" != "${source}" && "${CODEBASE_ROOT}" != "${source_root}" ]]; then
            run_cmd mv "${target}" "${target}.bak.$(date +%s)"
        fi

        if [[ "${target}" != "${source}" ]]; then
            run_cmd ln -sfn "${source}" "${target}"
        fi
    done

    # Clean up legacy .agents or .agent symlinks in target codebase
    for item in ".agents" ".agent"; do
        local legacy_link="${CODEBASE_ROOT}/${item}"
        if [[ -L "${legacy_link}" ]]; then
            local link_dest
            link_dest="$(readlink "${legacy_link}" || true)"
            if [[ "${link_dest}" == *"${EXTERNAL_BASE}"* || "${link_dest}" == *".agents"* ]]; then
                run_cmd rm -f "${legacy_link}"
                log_info "Removed legacy symlink ${legacy_link}"
            fi
        fi
    done
    log_info "Linked .ai and AGENTS.md into codebase at ${CODEBASE_ROOT}"

    # 8. Configure .git/info/exclude and Git hooks (supports standard repos, worktrees, submodules, and repo)
    if command -v git >/dev/null 2>&1 && git -C "${CODEBASE_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local git_common_dir
        git_common_dir="$(cd -- "${CODEBASE_ROOT}" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || (cd -- "${CODEBASE_ROOT}" && cd -- "$(git rev-parse --git-common-dir 2>/dev/null || git rev-parse --git-dir)" && pwd -P))"

        local exclude_file="${git_common_dir}/info/exclude"
        run_cmd mkdir -p "$(dirname -- "${exclude_file}")"
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would add symlinks to ${exclude_file}"
        else
            for item in "/.ai" "/AGENTS.md"; do
                if ! grep -Fqx "${item}" "${exclude_file}" 2>/dev/null; then
                    printf "%s\n" "${item}" >> "${exclude_file}"
                fi
            done
            log_info "Added symlinks to ${exclude_file}"
        fi

        # 9. Configure Git hooks idempotently (preserve existing hooks)
        local hooks_dir="${git_common_dir}/hooks"
        run_cmd mkdir -p "${hooks_dir}"

        for hook_name in "pre-commit" "post-merge"; do
            local hook_src="${source_root}/templates/hooks/${hook_name}"
            local hook_dst="${hooks_dir}/${hook_name}"
            [[ ! -f "${hook_src}" ]] && continue

            if [[ ! -f "${hook_dst}" ]]; then
                run_cmd cp "${hook_src}" "${hook_dst}"
                [[ "${DRY_RUN}" == "false" ]] && chmod +x "${hook_dst}"
            elif ! grep -Fq "sync_ai_kb.sh" "${hook_dst}" 2>/dev/null; then
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_info "[DRY-RUN] Would append ai-workspace hook block to existing ${hook_dst}"
                else
                    printf "\n# --- ai-workspace hook integration ---\n" >> "${hook_dst}"
                    grep -Ev '^(#!/|set -e)' "${hook_src}" >> "${hook_dst}"
                    chmod +x "${hook_dst}"
                fi
            fi
        done
        if [[ "${DRY_RUN}" == "false" ]]; then
            log_info "Configured Git hooks (pre-commit, post-merge) in ${hooks_dir}"
        fi
    fi

    log_success "Installation complete! Out-of-tree AI workspace is ready for: ${PROJECT_NAME}"
}

# Migrate an existing legacy AI workspace to the latest engine, schema, and layout without losing domain knowledge
migrate_workspace() {
    local source_root="$1"

    log_info "Starting AI Workspace migration for: ${PROJECT_NAME}"
    log_info "Target codebase root: ${CODEBASE_ROOT}"
    log_info "Target external storage: ${EXTERNAL_BASE}"

    if [[ ! -d "${EXTERNAL_BASE}" ]]; then
        log_warn "No existing external workspace found at ${EXTERNAL_BASE}. Running fresh provision instead."
        provision_workspace "${source_root}"
        return 0
    fi

    # 1. Preserve any uncommitted WIP in the external Git repository before upgrading
    if command -v git >/dev/null 2>&1 && [[ -d "${EXTERNAL_BASE}/.git" ]]; then
        if ! git -C "${EXTERNAL_BASE}" config user.email >/dev/null 2>&1; then
            git -C "${EXTERNAL_BASE}" config user.email "ai-workspace@local"
            git -C "${EXTERNAL_BASE}" config user.name "AI Workspace"
        fi
        if [[ -n "$(git -C "${EXTERNAL_BASE}" status --porcelain 2>/dev/null)" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY-RUN] Would commit pending WIP changes in ${EXTERNAL_BASE} before migration"
            else
                git -C "${EXTERNAL_BASE}" add -A
                git -C "${EXTERNAL_BASE}" commit -q -m "chore(kb): save pending knowledge WIP prior to workspace migration" || true
                log_info "Saved uncommitted knowledge changes in ${EXTERNAL_BASE}"
            fi
        fi
    fi

    # 2. Normalize legacy '**Status:**' headers in domain files to canonical '**Overall Status:**'
    if [[ -d "${DOMAINS_DIR}" ]]; then
        local normalized_cnt=0
        while IFS= read -r md_file; do
            [[ -z "${md_file}" || ! -f "${md_file}" ]] && continue
            if grep -Eq '^\*\*Status:\*\*' "${md_file}" && ! grep -Eq '^\*\*Overall Status:\*\*' "${md_file}"; then
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_info "[DRY-RUN] Would normalize '**Status:**' -> '**Overall Status:**' in ${md_file}"
                else
                    sed --follow-symlinks -i -E 's/^\*\*Status:\*\*/**Overall Status:**/' "${md_file}"
                fi
                normalized_cnt=$((normalized_cnt + 1))
            fi
        done < <(find "${DOMAINS_DIR}" -type f -name "*.md")
        if [[ "${normalized_cnt}" -gt 0 ]]; then
            log_info "Normalized status header in ${normalized_cnt} domain file(s)."
        fi
    fi

    # 3. Upgrade _template.md and AGENTS.md to latest canonical versions
    if [[ -f "${source_root}/templates/_template.md" ]]; then
        run_cmd cp "${source_root}/templates/_template.md" "${DOMAINS_DIR}/_template.md"
    fi
    if [[ -f "${source_root}/AGENTS.md" && "${source_root}/AGENTS.md" != "${EXTERNAL_BASE}/AGENTS.md" ]]; then
        run_cmd cp "${source_root}/AGENTS.md" "${EXTERNAL_BASE}/AGENTS.md"
        log_info "Upgraded AGENTS.md to latest canonical specification."
    fi

    # 4. Clean up legacy duplicate artifacts inside .ai/ root (from early versions)
    local -a legacy_artifacts=(
        "${AI_DIR}/docs"
        "${AI_DIR}/hooks"
        "${AI_DIR}/README.md"
        "${AI_DIR}/_template.md"
        "${EXTERNAL_BASE}/.agent"
        "${EXTERNAL_BASE}/.agents"
    )
    for artifact in "${legacy_artifacts[@]}"; do
        if [[ -e "${artifact}" || -L "${artifact}" ]]; then
            run_cmd rm -rf "${artifact}"
            log_info "Cleaned legacy artifact: ${artifact}"
        fi
    done

    # 5. Re-run provision_workspace to upgrade CLI binary, lib/*.sh, scripts/*.sh, global skills, symlinks, and Git hooks
    provision_workspace "${source_root}"

    # 6. Reindex and refresh drifted symbol coordinates across all domains
    registry_reindex
    local refreshed_cnt
    refreshed_cnt="$(registry_refresh_coords "")"
    if [[ "${refreshed_cnt}" -gt 0 ]]; then
        log_info "Refreshed drifted symbol coordinates in ${refreshed_cnt} domain(s)."
    fi

    # 7. Commit all migration upgrades cleanly to external knowledge Git repository
    if command -v git >/dev/null 2>&1 && [[ -d "${EXTERNAL_BASE}/.git" && "${DRY_RUN}" == "false" ]]; then
        if [[ -n "$(git -C "${EXTERNAL_BASE}" status --porcelain 2>/dev/null)" ]]; then
            git -C "${EXTERNAL_BASE}" add -A
            git -C "${EXTERNAL_BASE}" commit -q -m "chore: migrate AI workspace to latest engine and schema" || true
            log_info "Committed migration upgrades to external knowledge Git repository."
        fi
    fi

    log_success "Migration complete for: ${PROJECT_NAME}"
    registry_print_status
}
