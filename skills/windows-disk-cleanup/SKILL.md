---
name: windows-disk-cleanup
description: Analyzes and cleans disk space on Windows NTFS drives. Uses a WizTree-style top-down drill-down scan to discover what is consuming space, then interactively confirms with the user before cleanup. Detects WSL2 VHDX files and recommends the wsl-disk-cleanup skill when significant space can be reclaimed. Use when the user mentions disk space is low, wants to free up storage, clean caches, or optimize disk usage on Windows.
---

# Windows Disk Space Cleanup

## General Principles

1. **Scan first, act later**: Complete the full top-down analysis before suggesting any cleanups.
2. **Interactive confirmation**: Present all findings ranked by size, then ask the user which items to clean. Never delete without explicit approval.
3. **Record before/after**: Capture free space before and after cleanup to report results.
4. **Write .ps1 scripts**: Avoid inline PowerShell one-liners — write logic to `.ps1` files to prevent CJK encoding issues, then run with `powershell -ExecutionPolicy Bypass -File <script>`.
5. **Safe deletion only**: Never permanently delete user files. Cache and temp files can be removed directly. For user files, use system trash.

## Phase 1: Top-Down Drill-Down Scan (WizTree-style)

The core methodology: scan a directory level, find the biggest items, drill into those, repeat until you reach the actual space consumers. Like how WizTree visualizes disk usage as a treemap.

### Step 1: Drive Overview

```powershell
$drive = Get-PSDrive C
$usedGB = [math]::Round($drive.Used / 1GB, 2)
$freeGB = [math]::Round($drive.Free / 1GB, 2)
$totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
```

### Step 2: Level 1 — Root Folders

Enumerate every folder at the drive root, sorted by size descending. Report all folders >= 0.5 GB. Also check for large files at root level (`.vhdx`, `.iso`, `.dat`, `hiberfil.sys`, `pagefile.sys`, `swapfile.sys`).

```powershell
$folders = Get-ChildItem -Path 'C:\' -Directory -Force
foreach ($f in $folders) {
    $size = (Get-ChildItem $f.FullName -Recurse -Force -File -EA SilentlyContinue |
             Measure-Object Length -Sum).Sum
    $sizeGB = [math]::Round($size / 1GB, 2)
    if ($sizeGB -ge 0.5) { Write-Host "$sizeGB GB`t$($f.FullName)" }
}
```

Also check per-drive Recycle Bin size and system hidden files at root.

### Step 3: Level 2 — Drill Into the Biggest

Take the top 3-5 largest root folders and list their immediate subfolders with sizes. For example, if `Users` is the largest, scan `Users\<username>` subfolders; if one of those is `AppData`, scan `AppData\Local`, `AppData\Roaming`, etc.

### Step 4: Level 3+ — Keep Drilling

For any subfolder >= 1 GB, drill one more level. Repeat until you reach the actual items consuming space — specific cache directories, log folders, data files, old versions, etc.

**The goal**: Don't stop at "AppData is 60 GB" — keep going until you can say "AppData\Roaming\SomeApp\cache is 15 GB" or "AppData\Local\SomeApp\1.0.0 + 2.0.0 have old versions totaling 3 GB".

### Step 5: System Areas

Also scan these system-managed locations (report sizes, but don't drill in):

```powershell
# Check each and report size
$systemPaths = @(
    'C:\Windows\Temp',
    'C:\Windows\Installer',
    'C:\Windows\SoftwareDistribution\Download',
    'C:\Windows\WinSxS'
)
```

### Step 6: Content Analysis — Understand Before Presenting

Before presenting findings to the user, the agent MUST proactively analyze each discovered space consumer to determine what it is, why it exists, and what happens if it's removed. The goal: users should be able to make confident decisions in a single round of interaction, without needing to ask "what is this?" for each item.

**For each item >= 1 GB (or in the top 10 by size), the agent should:**

1. **Identify the owner application**: Infer from the path structure (e.g., `AppData\Local\Google\Chrome\User Data\Default\Cache` → Chrome browser cache). Check for version folders, app manifests, or recognizable directory patterns.

2. **Sample the contents**: List a few representative files inside the directory — file types, naming patterns, timestamps. This helps distinguish between "cache that regenerates automatically" vs "user data that's gone forever".
   ```powershell
   Get-ChildItem '<path>' -Force | Select-Object Name, Length, LastWriteTime | Sort-Object Length -Descending | Select-Object -First 10
   ```

3. **Classify the item** into one of these categories:
   - **Cache / Temp**: Auto-regenerated on next use. Safe to delete. Examples: browser cache, npm cache, pip cache, NuGet packages, build intermediates.
   - **Logs**: Historical records, usually not needed. Safe to delete, but note that debugging info is lost.
   - **Old versions / installers**: Previous versions of software kept alongside current versions. Safe if the current version works fine.
   - **Package manager store**: Shared dependency store (e.g., pnpm store, Yarn cache, Maven repo). Safe to delete but will re-download on next install.
   - **Application data**: User-generated or app-critical data (databases, configs, project files). NOT safe — warn the user explicitly.
   - **System-managed**: Windows-controlled directories (WinSxS, Installer). Use only official tools.

4. **Assess deletion impact**: Clearly state what happens after deletion:
   - "Will be rebuilt automatically next time you open Chrome" (zero user impact)
   - "You'll need to re-download packages on next `npm install`, may take a few minutes" (minor inconvenience)
   - "Contains your project databases — cannot be recovered" (data loss risk)

5. **Give a safety verdict**: Use clear labels:
   - ✅ Safe to clean — no user impact
   - ⚠️ Low risk — minor inconvenience (explain what)
   - ❌ Not recommended — contains user data or critical application state

### Step 7: Present Findings

Compile all discovered items into a single numbered list, sorted by size descending. For each item include:
- Size
- Full path
- What it is and what application it belongs to (from Step 6 analysis — NOT a vague guess)
- Deletion impact: what will happen if removed (specific, not generic)
- Safety verdict with label

The descriptions should be written in natural language that a non-technical user can understand. Avoid jargon. For example:
- GOOD: "Chrome browser cache (15.3 GB) — temporary files Chrome uses to load websites faster. Will be rebuilt automatically as you browse. No data loss."
- BAD: "Cache directory, safe to clean."

Use `AskUserQuestion` to let the user select which items to clean. Group items by safety level so safe items are easy to batch-select. Also always offer system-level cleanup tools:

```powershell
# Windows component store cleanup (elevated)
DISM /online /Cleanup-Image /StartComponentCleanup
# System disk cleanup utility
cleanmgr /d C /VERYLOWDISK
```

Never manually delete from `C:\Windows\Installer` or `C:\Windows\WinSxS` — only use the tools above.

## Phase 2: Execute Cleanup

After user confirms which items to clean:

1. Record current free space.
2. Clean each selected item. For locked files, skip and report.
3. For system cleanup, run DISM and cleanmgr elevated.
4. Record new free space and report per-item and total space freed.

## Phase 3: WSL2 Detection and Handoff

During the drill-down scan, if large `.vhdx` files are discovered (WSL2 virtual disks), assess whether WSL cleanup is worthwhile and guide the user to the dedicated skill.

### Step 1: Detect VHDX Files

If the scan finds `.vhdx` files (typically `ext4.vhdx` under `AppData\Local\Packages` or on other drives), report:
- VHDX file size on disk
- Actual usage inside WSL: `wsl.exe -d <distro> -e bash -c "df -h /"`
- The gap between the two (= reclaimable space)

### Step 2: Recommend WSL Cleanup

If the VHDX is significantly larger than actual WSL usage (e.g., gap > 10 GB), or if the VHDX is one of the top space consumers on the drive, inform the user:

- Explain that WSL2 VHDX files grow automatically but never shrink on their own.
- Tell the user they can use the **wsl-disk-cleanup** skill to scan inside WSL, clean up, and compact the VHDX to reclaim space.
- Report the estimated reclaimable space to help the user decide.

This skill does NOT perform WSL internal scanning or VHDX compaction itself — that workflow is handled entirely by the `wsl-disk-cleanup` skill.

## Phase 4: Post-Cleanup Report

1. **Summary**: List each cleaned item with space freed.
2. **Before/after**: Drive free space before vs after, for each drive cleaned.
3. **Optimization tips** (suggest where applicable):
   - Suggest scheduled cleanup for directories that grow fast.

## Error Handling

- **Locked files**: Skip and report. Note which process likely holds the lock.
- **Permission denied**: Try elevation via `Start-Process -Verb RunAs`. Report if still denied.
- **VHDX compaction has no effect**: Almost always means fstrim was not run. Go back and run it.
- **Encoding issues**: Always write PowerShell logic to `.ps1` files, never complex inline commands.
