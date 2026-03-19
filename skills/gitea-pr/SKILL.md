---
name: gitea-pr
description: Gitea PR skill for fetching PR information, viewing diffs, analyzing changes, and examining pull request details. Works with any Gitea server.
type: tool
---

# Gitea PR Skill

## Overview
Universal Gitea PR information retrieval skill. Fetches PR diffs, file changes, commit records, status info, and more. Configurable for any Gitea server.

**Scope**: Read-only operations for PR-related information:
- PR diffs and file changes
- PR basic info and status
- PR commit list and comments
- PR list and search

## Trigger Conditions
This skill activates when:
- User requests PR diff, file list, or commit records
- User references PR numbers (e.g., PR #83, #83, 查看 #83)
- User mentions "code review", "pull request", "merge request", "MR"
- User wants PR info, status, branches, comments, or any PR-related operation
- User asks "what open PRs exist", "has this PR been merged"

## Prerequisites
```bash
# 1. Get Gitea token from:
#    {GITEA_URL}/user/settings/applications
# 2. Export token
export GITEA_TOKEN="your_token_here"

# 3. Optional: Set default repository (format: owner/repo)
export GITEA_DEFAULT_REPO="owner/repository"
```

## Configuration Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `GITEA_URL` | Gitea server URL | `https://gitea.example.com` |
| `GITEA_TOKEN` | Authentication token | `gho_xxxxxxxxxxxx` |
| `GITEA_DEFAULT_REPO` | Default repository | `myorg/myproject` |
| `GITEA_DEFAULT_BRANCH` | Default branch | `main` |

## API Patterns

### 1. **View PR Diff (Simplest - URL suffix)**
```bash
# View diff (plain text)
# URL format: {GITEA_URL}/{owner}/{repo}/pulls/{PR_NUMBER}.diff
curl -s "${GITEA_URL}/${REPO}/pulls/${PR_NUMBER}.diff"

# With authentication
curl -s -H "Authorization: token $GITEA_TOKEN" \
  "${GITEA_URL}/${REPO}/pulls/${PR_NUMBER}.diff"

# Get patch format
curl -s -H "Authorization: token $GITEA_TOKEN" \
  "${GITEA_URL}/${REPO}/pulls/${PR_NUMBER}.patch"
```

### 2. **Use Gitea API**
```bash
# View PR changed files list
# API format: /api/v1/repos/{owner}/{repo}/pulls/{PR_NUMBER}/files
curl -s "${GITEA_URL}/api/v1/repos/${REPO}/pulls/${PR_NUMBER}/files" \
  -H "Authorization: token $GITEA_TOKEN"

# View PR basic info (includes base/head branch names)
curl -s "${GITEA_URL}/api/v1/repos/${REPO}/pulls/${PR_NUMBER}" \
  -H "Authorization: token $GITEA_TOKEN"

# Get PR list
curl -s "${GITEA_URL}/api/v1/repos/${REPO}/pulls?state=all" \
  -H "Authorization: token $GITEA_TOKEN"

# View commit list
curl -s "${GITEA_URL}/api/v1/repos/${REPO}/pulls/${PR_NUMBER}/commits" \
  -H "Authorization: token $GITEA_TOKEN"
```

### 3. **Use Git for Local Comparison**
```bash
# Fetch PR head branch to local
git fetch origin refs/pull/${PR_NUMBER}/head:pr-${PR_NUMBER}

# View diff
git diff ${DEFAULT_BRANCH:-main}..pr-${PR_NUMBER}

# List only changed files
git diff --name-only ${DEFAULT_BRANCH:-main}..pr-${PR_NUMBER}

# Show diff stats
git diff --stat ${DEFAULT_BRANCH:-main}..pr-${PR_NUMBER}
```

## Implementation Flow

### When user requests PR diff:
1. **Parse PR number** - Extract from user input (supports Chinese and English)
2. **Check GITEA_TOKEN** - Verify environment variable exists
3. **Fetch PR info** - Use API to get basic PR information
4. **Fetch diff** - Get `.diff` or `.patch` format
5. **Analyze changes** - Parse and summarize key modifications
6. **Display results** - Show in clean, readable format

### When user requests file list:
1. **Call files API** - `/api/v1/repos/{owner}/{repo}/pulls/{N}/files`
2. **Parse JSON** - Extract filename, additions, deletions, changes
3. **Calculate stats** - Total files, lines added/removed
4. **Display summary** - Show with breakdown

## Examples

### Example 1: View PR Diff
**User request**: "View PR #123 diff"

**Skill response**:
```
✅ Fetching PR #123 diff from Gitea...

📊 PR #123 Info:
- Title: [title from API]
- Status: open
- Author: [username]
- Branch: feature/xxx → main

📈 Change Statistics:
- Total files: {count}
- Lines added: +{additions}
- Lines deleted: -{deletions}
- Net change: +{net}

📁 Main Changed Files:
1. src/main.go (+45, -12)
2. pkg/config.yaml (+89, -23)
3. README.md (+12, -0)

🔍 Key Changes:
- [list key changes]

📋 Full Diff:
[show first 50 key diff lines]
```

### Example 2: Get File List
**User request**: "Get PR #123 file list"

**Skill response**:
```
📁 PR #123 Changed Files:

1. src/main.go
   📊 Changes: +45 lines, -12 lines

2. pkg/config.yaml
   📊 Changes: +89 lines, -23 lines

... [list all files]

📈 Summary:
- Files: {count}
- Lines added: +{additions}
- Lines deleted: -{deletions}
```

### Example 3: PR Basic Info
**User request**: "PR #123 basic info"

**Skill response**:
```
📋 PR #123 Basic Info:

Title: [title from API]
Status: open/closed/merged
Author: [username]
Created: [timestamp]

Branch Info:
- Base: [target branch]
- Head: [source branch]

Labels: [if any]
Milestone: [if any]

🔗 Links:
- Gitea page: {GITEA_URL}/{REPO}/pulls/123
- Diff link: {GITEA_URL}/{REPO}/pulls/123.diff
```

## Error Handling

### Missing Token
```bash
if [ -z "$GITEA_TOKEN" ]; then
  echo "❌ Gitea token not set. Please run:"
  echo "export GITEA_TOKEN=\"your_token_here\""
  echo "Get token: ${GITEA_URL:-http://localhost:3000}/user/settings/applications"
  exit 1
fi
```

### Missing Configuration
```bash
if [ -z "$GITEA_URL" ]; then
  echo "❌ GITEA_URL not set. Please run:"
  echo "export GITEA_URL=\"https://gitea.example.com\""
  exit 1
fi

if [ -z "$REPO" ]; then
  if [ -z "$GITEA_DEFAULT_REPO" ]; then
    echo "❌ Repository not specified. Set REPO or GITEA_DEFAULT_REPO"
    echo "Example: export GITEA_DEFAULT_REPO=\"owner/repository\""
    exit 1
  fi
  REPO="$GITEA_DEFAULT_REPO"
fi
```

### Invalid PR Number
```bash
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "❌ Invalid PR number: $PR_NUMBER"
  echo "Use a valid PR number, e.g.: 83, 103"
  exit 1
fi
```

### API Errors
```bash
if [ "$HTTP_CODE" -ne 200 ]; then
  echo "❌ Gitea API error (HTTP $HTTP_CODE)"
  echo "Possible reasons:"
  echo "1. PR doesn't exist or no access"
  echo "2. Token invalid or expired"
  echo "3. Gitea server issue"
  echo "4. Incorrect repository path: $REPO"
  exit 1
fi
```

## Helper Functions

### Extract PR Number
```bash
extract_pr_number() {
  # Supports: "PR #83", "查看 #83", "pr83", "#83", "83"
  local input="$1"
  echo "$input" | grep -o '[0-9]\+' | head -1
}
```

### Format Diff Output
```bash
format_diff() {
  local diff_content="$1"
  local max_lines="${2:-50}"
  # Highlight key changes, filter noise
  echo "$diff_content" | \
    grep -E '^[+\-].*|^@@.*|^diff.*|^---.*|^\+\+\+.*' | \
    head -"$max_lines"
}
```

### Calculate Stats
```bash
calculate_stats() {
  local diff_content="$1"
  local additions=$(echo "$diff_content" | grep '^+' | grep -v '^+++' | wc -l)
  local deletions=$(echo "$diff_content" | grep '^-' | grep -v '^---' | wc -l)
  echo "additions:$additions deletions:$deletions"
}
```

### Parse Files API Response
```bash
parse_files_json() {
  local json="$1"
  # Use jq if available
  if command -v jq &> /dev/null; then
    echo "$json" | jq -r '.[] | "\(.filename): +\(.additions) -\(.deletions)"'
  else
    # Simple text parsing
    echo "$json" | grep -o '"filename":"[^"]*"' | cut -d'"' -f4
  fi
}
```

## Integration Examples

### Full Diff Analysis
1. Fetch PR info → Show basic details
2. Fetch diff → Calculate statistics
3. Parse files → List modified files
4. Analyze changes → Highlight key modifications
5. Present → Clean summary with full diff available

### Quick Review
1. Fetch diff only → Show concise summary
2. Calculate stats → Provide overview
3. Suggest review → Point to key files

### File-centric Review
1. Fetch files list → Show all modified files
2. Get per-file diffs → Allow drill-down
3. Group by type → Organize by file category

## Best Practices

1. **Always authenticate** - Use $GITEA_TOKEN for all API calls
2. **Handle errors gracefully** - Provide helpful error messages
3. **Cache when appropriate** - For multiple operations on same PR
4. **Respect rate limits** - Add delays if needed
5. **Format output clearly** - Use emojis, sections, summaries
6. **Provide actionable insights** - Not just raw data
7. **Use configuration** - Keep config flexible via environment variables

## Notes
- API version: v1
- Supports Gitea self-hosted and enterprise editions
- Some API may vary slightly depending on Gitea version
