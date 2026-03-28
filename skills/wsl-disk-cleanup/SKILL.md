---
name: wsl-disk-cleanup
description: Analyzes and cleans disk space inside WSL2 Linux distributions, then compacts the VHDX virtual disk to reclaim space on the Windows host. Uses a top-down drill-down scan (like du-based treemap) to discover space consumers inside WSL, interactively confirms with the user, and executes the full compaction workflow (clean, fstrim, shutdown, compact, verify, restart). Use when the user wants to free WSL disk space, shrink VHDX, or when a Windows disk scan reveals large VHDX files.
---

# WSL2 Disk Space Cleanup

## Why WSL2 Needs Special Handling

WSL2 stores its Linux filesystem in a VHDX virtual disk file on the Windows host. This file **grows automatically** as data is written inside WSL, but **never shrinks on its own** — even after files are deleted inside WSL, the VHDX stays the same size. Reclaiming space requires a specific workflow: clean inside WSL, then compact the VHDX from the Windows side.

## General Principles

1. **Same scanning methodology as Windows disk cleanup**: Use a top-down drill-down approach — scan a directory level, find the biggest items, drill into those, repeat until you reach the actual space consumers.
2. **Interactive confirmation**: Present all findings ranked by size. Never delete without user approval.
3. **Record before/after**: Capture VHDX size and host drive free space before and after the full process.
4. **Write .ps1 scripts**: For PowerShell commands on the Windows side, write to `.ps1` files to avoid CJK encoding issues, then run with `powershell -ExecutionPolicy Bypass -File <script>`.

## Phase 1: Assess VHDX and Reclaimable Space

### Step 1: List WSL Distributions

```bash
wsl.exe -l -v
```

Identify the distro name and whether it's running.

### Step 2: Locate VHDX Files

Search common locations for `.vhdx` files:

```powershell
# Default location (Microsoft Store installs)
Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Recurse -Filter "ext4.vhdx" -Force -Depth 4

# Also search other drives — users often move WSL to D:, E:, etc.
Get-ChildItem -Path "D:\" -Recurse -Filter "*.vhdx" -Force -Depth 3
```

Report each VHDX file path and size on disk.

### Step 3: Compare VHDX Size vs Actual Usage

```bash
wsl.exe -d <distro> -e bash -c "df -h /"
```

Compare: if VHDX is 200 GB on disk but WSL only uses 80 GB, there's ~120 GB potentially reclaimable. Present this gap to the user — it motivates the cleanup.

## Phase 2: Top-Down Drill-Down Scan Inside WSL

Use the same WizTree-style methodology as a Windows disk scan, but with Linux tools (`du`).

### Step 1: Level 1 — Top-Level Directories

Dynamically enumerate all directories under `/`, sorted by size, just like the Windows skill scans all root folders:

```bash
wsl.exe -d <distro> -e bash -c "du -h --max-depth=1 / 2>/dev/null | sort -rh | head -20"
```

This catches all directories including non-standard ones users may have created.

### Step 2: Level 2+ — Drill Into the Biggest

Take the largest directories from Level 1 and drill in:

```bash
wsl.exe -d <distro> -e bash -c "du -h --max-depth=1 <path> 2>/dev/null | sort -rh | head -20"
```

### Step 3: Keep Drilling

Repeat for any subfolder >= 1 GB. Do NOT stop at a high-level summary.

**The goal**: Don't report "/root is 100 GB" — keep going until you can say "/root/.some-tool/data/cache is 35 GB" or "/root/.some-server/data/User/globalStorage/some-extension/tasks is 39 GB".

The agent should infer what each discovered item is from the folder name, parent path, and contents — not from a hardcoded lookup table. Every WSL environment is different.

### Step 4: Present Findings and Confirm

Compile all discovered items into a numbered list, sorted by size descending. For each item:
- Size
- Full path
- Brief description (what it appears to be)
- Safety assessment (safe to clean / ask user / don't touch)

Use `AskUserQuestion` to let the user select which items to clean.

## Phase 3: Clean Inside WSL

Execute deletions for user-approved items:

```bash
wsl.exe -d <distro> -e bash -c "du -sh <path> && rm -rf <path> && echo 'deleted'"
```

For package-manager or runtime caches, prefer using the tool's own cleanup command when available (the agent should recognize these from context).

After cleaning, verify new usage:

```bash
wsl.exe -d <distro> -e bash -c "df -h /"
```

## Phase 4: Compact VHDX (Reclaim Space on Host)

This is the critical multi-step process that actually returns space to the Windows drive.

### Step 1: fstrim — Mark Free Blocks (Do NOT Skip)

```bash
wsl.exe -d <distro> -e bash -c "fstrim -v /"
```

**This step is mandatory.** Without fstrim, deleted data blocks inside the ext4 filesystem are not zeroed out. The VHDX compaction relies on detecting zero-filled blocks to shrink the file. If you skip fstrim, compaction will have NO effect — this is the #1 reason VHDX compaction fails.

### Step 2: Shutdown WSL

```bash
wsl.exe --shutdown
```

Wait for shutdown to complete. The VHDX file must not be in use during compaction.

### Step 3: Record VHDX Size Before Compaction

```powershell
[math]::Round((Get-Item '<vhdx-path>' -Force).Length / 1GB, 2)
```

### Step 4: Compact VHDX

**Method 1** — `Optimize-VHD` (preferred, requires Hyper-V module):

```powershell
Start-Process powershell -ArgumentList '-Command','Optimize-VHD -Path ''<vhdx-path>'' -Mode Full' -Verb RunAs -Wait
```

**Method 2** — `diskpart` fallback (if Optimize-VHD unavailable):

Write a script file:
```
select vdisk file="<vhdx-path>"
attach vdisk readonly
compact vdisk
detach vdisk
exit
```

Execute:
```powershell
Start-Process diskpart -ArgumentList '/s','<script-path>' -Verb RunAs -Wait
```

**If VHDX size doesn't change**: Go back and run fstrim (Step 1). This is almost always the cause.

### Step 5: Verify

1. Check VHDX size after compaction.
2. Check host drive free space.
3. Report the delta: "VHDX shrank from X GB to Y GB, host drive freed Z GB."

### Step 6: Restart WSL

```bash
wsl.exe -d <distro> -e bash -c "echo 'WSL started successfully' && df -h /"
```

## Phase 5: Post-Cleanup Report and Recommendations

1. **Summary**: List each cleaned item with space freed inside WSL.
2. **VHDX compaction result**: Before/after VHDX size and host drive free space.
3. **Optimization tips** (suggest where applicable):
   - `sparseVhd=true` in `%USERPROFILE%\.wslconfig` — enables automatic VHDX space reclamation, eliminating the need for manual fstrim + compact cycles. **IMPORTANT**: This setting must be placed under the `[experimental]` section, NOT under `[wsl2]`. Requires WSL 2.0.4+. Correct format:

     ```ini
     [wsl2]
     memory=8GB

     [experimental]
     sparseVhd=true
     ```

   - Adjust WSL memory/swap in `.wslconfig` if swap.vhdx is consuming extra space.
   - Identify fast-growing directories and suggest periodic cleanup.

## Example: Full Cleanup Session

Below is a condensed example of a real WSL cleanup session showing the key steps and expected output at each stage.

### 1. Assess VHDX vs Actual Usage

```
> powershell: (Get-Item 'D:\wslWorkSpace\ext4.vhdx').Length / 1GB
217.83 GB                              # VHDX size on disk

> wsl.exe -d Ubuntu -e bash -c "df -h /"
Filesystem  Size  Used Avail Use%
/dev/sdd   1007G  153G  804G  16%     # Only 153 GB actually used
                                       # Gap: 217 - 153 = ~65 GB reclaimable
```

### 2. Top-Down Drill-Down Scan

```
> Level 1: du -h --max-depth=1 /
109G  /root          # <-- biggest, drill in
20G   /home
18G   /var
9.3G  /usr

> Level 2: du -h --max-depth=1 /root
43G   /root/.vscode-server    # <-- drill in
26G   /root/.zarf-cache
13G   /root/.local            # <-- drill in
5.9G  /root/.kapp

> Level 3: du -h --max-depth=1 /root/.vscode-server
40G   /root/.vscode-server/data
2.2G  /root/.vscode-server/extensions

> Level 4: du -h --max-depth=1 /root/.vscode-server/data/User
39G   /root/.vscode-server/data/User/globalStorage

> Level 5: du -h --max-depth=1 .../globalStorage
39G   .../globalStorage/kilocode.kilo-code    # Found it! An extension's task history = 39 GB
```

Keep drilling every branch until you reach the actual item consuming space.

### 3. Present Findings to User (example output)

```
1. Kilo-Code task history — 39 GB    /root/.vscode-server/.../kilocode.kilo-code/tasks
2. Zarf image cache — 26 GB          /root/.zarf-cache/images
3. OpenCode logs — 11 GB             /root/.local/share/opencode/log
4. kapp cache — 5.9 GB               /root/.kapp
5. ...
```

Ask user which items to clean → User selects 1, 2, 3, 4.

### 4. Clean, fstrim, Compact

```
> Clean inside WSL:
rm -rf /root/.vscode-server/.../tasks     # 39 GB
rm -rf /root/.zarf-cache                   # 26 GB
rm -rf /root/.local/share/opencode/log     # 11 GB
rm -rf /root/.kapp                         # 5.9 GB

> Verify: df -h /
Used: 153G → 68G  (freed ~85 GB inside WSL)

> fstrim (CRITICAL):
fstrim -v /
/: 922 GiB trimmed                         # Marks free blocks for compaction

> Shutdown WSL:
wsl.exe --shutdown

> Compact VHDX:
Optimize-VHD -Path 'D:\wslWorkSpace\ext4.vhdx' -Mode Full

> Result:
VHDX: 217 GB → 117 GB (sparse)
Host D: free: 25 GB → 126 GB              # 101 GB reclaimed on host!

> Restart WSL:
wsl.exe -d Ubuntu                          # Verify WSL starts OK
```

## Error Handling

- **fstrim fails**: May require root. Try `sudo fstrim -v /`.
- **Optimize-VHD permission denied**: Must run as Administrator. Use `Start-Process -Verb RunAs`.
- **VHDX compaction has no effect**: fstrim was not run, or WSL was not fully shut down. Verify both.
- **Locked VHDX**: WSL is still running. Run `wsl.exe --shutdown` and verify with `wsl.exe -l -v` that state is "Stopped".
- **Encoding issues**: Write PowerShell logic to `.ps1` files instead of inline commands.
