# Smart Commit Generator Skill

**Purpose:** This skill is used by Antigravity to automatically analyze the current state of a repository, cross-reference it with the user's conversation history, and generate a contextual Conventional Commit message.

**Trigger:** The user asks to "draft a commit", "generate a commit message", or run this skill.

---

### Step 1: Analyze Code Changes
1. Use the `run_command` tool to execute `git status`.
2. Use the `run_command` tool to execute `git diff HEAD`. Limit the output output size if it expects to be massive.
3. Review the outputs to understand exactly which files were heavily modified, added, or deleted, and what structural changes occurred.

### Step 2: Contextualize with History
1. Review my `Persistent Context` knowledge. Look specifically at **Conversation Summaries** for the recent conversation paths that match the current repository domain and changes.
2. Read the latest artifacts in the current conversation log (`walkthrough.md`, `implementation_plan.md`, `task.md`) for high-level motivation, user decisions, constraints, and intent.
3. Determine *why* these code changes were implemented (e.g., bug fix, new layout feature, refactoring).

### Step 3: Format the Commit Message (Conventional Commits)
Draft a strict **Conventional Commits** formatted message. 
- Use types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Include an optional scope if relevant (e.g., `feat(ui): ...`).
- Subject line max 50 characters, written in imperative mood (e.g., "Add feature", not "Added feature" or "Adds feature").
- In the body, explain the **intent/why** (from conversation history) and a brief overview of the **what** (from the `git diff`). Use bullet points if necessary.
- Wrap the body logically at ~72 characters.

**Standard Template:**
```
<type>[optional scope]: <description>

[optional body describing the 'what' and 'why' based on history and diff]
```

### Step 4: Save and Preview
Use the `write_to_file` (with Overwrite) tool to save the drafted commit message to a file named `NEXT_COMMIT.txt` in the active repository's root directory. After it has been written, politely inform the user that the `NEXT_COMMIT.txt` file has been created or updated so they can preview it, copy it, or `git commit -F NEXT_COMMIT.txt` via their IDE.

### Step 5: Generate CurseForge Changelog Entry
Using the same context gathered in Steps 1-2, produce a **user-facing changelog summary** suitable for pasting into the CurseForge file description / version changelog. This is what *players* will read — it must avoid developer jargon, Conventional Commit prefixes, and internal file references.

Guidelines:
- Write from the player's perspective ("You can now...", "Fixed an issue where...").
- Group entries under headings using markdown: `## New Features`, `## Bug Fixes`, `## Changes`.
- Each bullet should be a single, plain-English sentence describing the observable change or fix.
- Omit internal refactors, code style changes, or anything invisible to the end user.
- Keep it concise — aim for clarity over completeness.

Save the result using `write_to_file` (with Overwrite) to a file named `NEXT_CHANGELOG.md` in the active repository's root directory. Inform the user the file is ready to be copied into the CurseForge changelog for the new version.

### Step 6: Update README.md Feature List
Read `README.md` and compare its `## Features` section against the new user-visible features identified in Steps 1–2.

Guidelines:
- Only consider changes that are observable by the end user (new UI controls, new automation behaviors, new set management capabilities, etc.). Skip internal refactors, bug fixes, and code-only changes.
- For each genuinely new feature, determine the appropriate existing sub-section in `## Features` (e.g., "Set Management", "Automated Event Engine", "User Interface & Integration") or create a new sub-section if none fits.
- Append new bullet points using the same style as existing entries: `**Bold Label**: Short description sentence.`
- Do **not** remove, reword, or restructure any existing bullets — only add.
- If no new user-visible features exist, skip this step entirely and do not modify the file.

If changes are needed, use `multi_replace_file_content` (or `replace_file_content`) to patch only the affected section(s) of `README.md`. Inform the user which feature bullets were added, or confirm that no README update was needed.

### Step 7: Bump Version in the Addon .toc File
Use `run_command` to find the `.toc` file in the repository root (`Get-ChildItem -Path . -Filter *.toc -Depth 0` or equivalent). There should be exactly one — use whichever is found. Read it and locate the `## Version:` line. Increment the version number using **semver** (`MAJOR.MINOR.PATCH`) according to the nature of the changes identified in Steps 1–2:

| Change type | Which segment to bump |
|---|---|
| New user-visible feature(s) (`feat`) | **MINOR** — reset PATCH to 0 |
| Bug fix(es) only (`fix`) | **PATCH** |
| Breaking change or major redesign | **MAJOR** — reset MINOR and PATCH to 0 |
| Docs / chore / refactor only | **PATCH** (still ship a new version so CurseForge detects the upload) |

Rules:
- Always bump exactly one segment; never bump more than one in the same commit.
- When in doubt between MINOR and PATCH, prefer MINOR if any new UI control or gameplay behavior was added.
- Use `replace_file_content` to update **only** the `## Version:` line in the discovered `.toc` file.
- Inform the user of the filename, the old version, the new version, and the rule that triggered the bump.

### Step 8: Final Deploy to WoW Addon Folder
Now that all files are updated — commit message, changelog, README, and version — run a final deploy so the WoW addon folder reflects the complete, versioned state ready for zipping and uploading to CurseForge.

Check that `deploy.ps1` exists in the repository root, then run it:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\deploy.ps1
```

- **Cwd**: the active repository root
- **SafeToAutoRun**: `false` — always request user approval before running.
- **WaitMsBeforeAsync**: `10000`

If the deploy **succeeds**, confirm with the new version number (e.g., "✅ vX.Y.Z deployed to the WoW addon folder — all files are up to date and ready to zip for CurseForge.").
If it **fails** or `deploy.ps1` is not found, report the error output and ask the user how to proceed. Do not silently skip.

### Step 9: Commit, Clean Up, and Package for CurseForge

#### 9a — Commit the changes
Run the git commit using the prepared `NEXT_COMMIT.txt`:

```powershell
git commit -a -F NEXT_COMMIT.txt
```

- **Cwd**: the active repository root
- **SafeToAutoRun**: `false` — request user approval.
- **WaitMsBeforeAsync**: `10000`

#### 9b — Grab the commit hash
After a successful commit, retrieve the short hash of the new HEAD:

```powershell
git rev-parse --short HEAD
```

Capture the output — this is `<hash>`. The zip will be named `<AddonName>-<hash>.zip` (e.g., `EqManager-a1b2c3d.zip`). The addon name is the `.toc` basename discovered in Step 7.

#### 9c — Remove stale zips from the WoW AddOns folder
Resolve the WoW AddOns folder the same way `deploy.ps1` does — read `wow_paths.json` in the repo root, fall back to the default Battle.net path if needed. The AddOns folder is the parent of `<TargetDir>` (i.e., `<wowAddonsPath>`). Scan it for any zip files whose name starts with `<AddonName>-` and delete them all:

```powershell
# Resolve the same path deploy.ps1 would use
$config      = Get-Content (Join-Path $repoRoot "wow_paths.json") -Raw | ConvertFrom-Json
$addonsDir   = $config.wowAddonPath   # already the AddOns folder
Get-ChildItem -Path $addonsDir -Filter "$addonName-*.zip" | Remove-Item -Force
```

Report each file removed (filename only). If none are found, confirm that no stale zips were present.

#### 9d — Create the versioned CurseForge zip
Zip the deployed addon folder into the AddOns directory as `<AddonName>-<hash>.zip`. The zip must contain the addon inside a folder named `<AddonName>` — this is the structure CurseForge and players expect when extracting directly into their AddOns folder.

Files excluded by `.curseignore` are already absent from the deployed folder (deploy.ps1 respects it), so `Compress-Archive` on the deployed folder produces the correct package:

```powershell
$zipPath = Join-Path $addonsDir "$addonName-$hash.zip"
Compress-Archive -Path $TargetDir -DestinationPath $zipPath -Force
```

- **SafeToAutoRun**: `false` — request user approval before creating the zip.

On success, confirm the full path of the zip (e.g., "✅ `EqManager-a1b2c3d.zip` written to the AddOns folder — upload this to CurseForge.").

> **Note:** The `.githooks/post-commit` hook runs `deploy.ps1` then `package.ps1` automatically after every `git commit`, so this zip is also created without running the skill. Steps 9c–9d here serve as a fallback if the hook wasn't triggered or needs to be re-run manually.


