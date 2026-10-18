# Public-repository safety and local milestone workflow

**No push is authorized or attempted. No local commit has been made.** Terminal execution was available for the deployment and experiments, but no Git status/history review or secret scan has been completed. Do not fabricate commit IDs or treat editor saves as commits.

## Disclosure policy

Publish only generic infrastructure code, sanitized templates and English learning records. Never commit actual subscription/tenant/principal/account IDs, VM/resource names that identify an organization, actual private/public IPs or CIDRs, customer identifiers, internal network/firewall settings, raw diagnostic logs, browser sessions, credentials, tokens, secrets or key material. The Microsoft-published AzureDatabricks application ID in source is a **public well-known application identifier**, not a tenant/subscription ID or a secret.

`.local/`, `evidence/`, local parameter variants, credentials/key file extensions and logs are excluded by the repository ignore rules. Ignoring a path does **not** untrack a previously tracked file or erase historical disclosure. Never use forced-add on evidence or local configuration. Prefer no identifying Git metadata in public code examples; inspect author name/email and remote URL privately before publication.

## Required local review before milestone commit

1. Restore execution, inspect `git status --short` and the initial tracked-file list/history. Do not assume no pre-existing changes. Inspect remote URL privately without printing embedded credentials.
2. Verify ignored local configuration/evidence with `git check-ignore`; verify no such files are already tracked with `git ls-files`. Review every intended staged file and diff, not only scanner output.
3. Run a trusted secret scanner, such as **Gitleaks**, on the working tree/staged contents **and all reachable Git history**. Inspect installed scanner version/help; do not invent a passed scan if unavailable. Scanner reports may themselves contain secrets; keep them in ignored local storage and print only redacted summaries. Do not install software silently on the existing VM.
4. Also check forbidden identifiers and real network addresses manually/with an organization-approved disclosure scan. Secret scanners alone do not reliably flag tenant IDs, subscription IDs, internal CIDRs or customer names. Review notebooks/outputs, diagrams and image metadata if later added.
5. Validate local Markdown links, PowerShell parsing/PSScriptAnalyzer if available, and eventually Bicep compilation when templates exist. Editor diagnostics are not execution tests.
6. Stage an explicit reviewed file allowlist, inspect the staged diff and staged-file list, then commit locally with a descriptive message such as `docs: record Phase 1 private-only CMK feasibility and deployment gates`. Use only already configured approved Git identity; ask rather than setting a global name/email. Do not stage unknown pre-existing work or raw evidence.
7. Record actual commit hash/date and scan results in progress/journal only after successful execution. Never push as part of a local commit script.

## Before public push (separate explicit approval)

- Obtain organizational open-source/disclosure clearance and explicit owner authorization for the target remote/branch/content.
- Repeat full tracked-file, staged-file and **entire reachable history** review; local-only ignore rules are not enough.
- If a credential was exposed, revoke/rotate first and get approval for any required history rewrite. Do not rewrite history silently or assume deletion from the latest tree fixes history.
- Verify sanitized results match actual experiments and retain needed private evidence under approved local controls.
- Push only the explicitly approved scope; no publication has been performed in Phase 1.

## Current check status

| Check | Actual state |
| --- | --- |
| New authored content reviewed for disclosure | Reviewed via authored content/partial editor Git diff and limited disclosure-pattern search; raw Azure metadata is retained only in ignored local evidence and sanitized in public docs; not a full secret scan |
| Workspace editor diagnostics | Final recheck reports no errors after Markdown formatting fixes; PowerShell runtime execution and external lint not performed |
| Secret scanner execution | Not run; no scan result claimed |
| Git tracked-file/history/staged review | Not run; repository status/history not yet verified |
| Local milestone commit | Not made; awaiting review and explicit milestone decision |
| Public publication | Not approved; not attempted |
