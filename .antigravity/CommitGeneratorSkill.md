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
