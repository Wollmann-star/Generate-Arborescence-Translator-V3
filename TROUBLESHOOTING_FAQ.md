# Troubleshooting & FAQ Guide

## Table of Contents

1. [Common Issues](#common-issues)
2. [Frequently Asked Questions](#frequently-asked-questions)
3. [Advanced Troubleshooting](#advanced-troubleshooting)
4. [Recovery Procedures](#recovery-procedures)
5. [Performance Optimization](#performance-optimization)
6. [Known Limitations](#known-limitations)

---

## Common Issues

### ❌ Issue 1: "Script cannot be loaded because running scripts is disabled"

**Error message:**
```
File ...\Generate-Arborescence-Translator-V3.ps1 cannot be loaded because 
running scripts is disabled on this system.
```

**Cause:** PowerShell execution policy prevents script execution.

**Solutions:**

**Option A: Temporary (current session only)**
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Generate-Arborescence-Translator-V3.ps1
```

**Option B: Permanent (for current user)**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Option C: Run as Administrator (if policy requires)**
```powershell
# Right-click PowerShell → "Run as Administrator"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
```

**Option D: Dot-source the script**
```powershell
. .\Generate-Arborescence-Translator-V3.ps1
```

**Security note:** Only change execution policy for scripts you trust. `RemoteSigned` requires downloaded scripts to be signed; `Bypass` allows all scripts.

---

### ❌ Issue 2: Translation operations are very slow

**Symptoms:**
- Script takes 10+ minutes for a small directory
- Frequent network timeouts
- Translation appears to hang

**Diagnosis:**

Check network latency to Google Translate:
```powershell
# Test API endpoint
Invoke-WebRequest -Uri "https://translate.googleapis.com/translate_a/single?client=gtx&sl=zh-CN&tl=en&dt=t&q=test" -TimeoutSec 5

# Measure response time
Measure-Command {
    Invoke-WebRequest -Uri "https://translate.googleapis.com/..." -TimeoutSec 5
}
```

**Solutions:**

**Solution 1: Use WhatIf mode first (preview-only, no translation)**
```powershell
.\script.ps1 -RootPath "D:\Data" -WhatIf
# This generates the report structure without translating
```

**Solution 2: Reduce retry count**
```powershell
.\script.ps1 -RootPath "D:\Data" -MaxTranslationRetries 1
# Fail fast instead of retrying 3 times
```

**Solution 3: Skip translation (detection only)**
```powershell
.\script.ps1 -RootPath "D:\Data" -SkipTranslation
# Just find Chinese characters, don't translate
```

**Solution 4: Check internet connection**
```powershell
# Test DNS and routing
Test-NetConnection -ComputerName translate.googleapis.com -Port 443

# Check proxy settings
[System.Net.ServicePointManager]::DefaultConnectionLimit = 10
```

**Solution 5: Use fallback translation service**
```powershell
.\script.ps1 -RootPath "D:\Data" -TranslationService Manual
# Returns [TRANS] prefix instead of API call
```

**Permanent workaround:** Add custom translation dictionary

Create `translations.json`:
```json
{
  "项目": "Project",
  "文档": "Documents",
  "说明": "README"
}
```

Modify script to load dictionary before API:
```powershell
$translationDict = Get-Content "translations.json" | ConvertFrom-Json
```

---

### ❌ Issue 3: "Access to the path is denied" during rename

**Error message:**
```
Access to the path 'D:\Data\项目' is denied
```

**Cause:** Insufficient permissions or file locked by another process.

**Solutions:**

**Solution 1: Run as Administrator**
```powershell
# Right-click PowerShell → "Run as Administrator"
.\script.ps1 -RootPath "D:\Data"
```

**Solution 2: Close locking applications**

Close any applications that might be accessing files:
- Windows Explorer (viewing the directory)
- IDE or code editor (open project)
- Antivirus (real-time scanning)
- Backup software (file lock)
- Cloud sync (OneDrive, Google Drive, Dropbox)

**Solution 3: Check file locks**
```powershell
# List open files in the directory (requires admin)
Get-Process | Select-Object -ExpandProperty Modules | Where-Object FileName -like "D:\Data\*"

# Or use Resource Monitor (GUI)
# Press Ctrl+Shift+Esc → Resource Monitor → Disk tab → Search for folder
```

**Solution 4: Retry with backoff**
```powershell
# Modify Invoke-SafeRename to retry on permission error:
# Add: Start-Sleep -Milliseconds 500 before second attempt
```

**Solution 5: Run outside business hours**
If antivirus/backup is the culprit:
```powershell
# Schedule for off-hours in Task Scheduler
$trigger = New-ScheduledTaskTrigger -AtLogOn
$action = New-ScheduledTaskAction -Execute "powershell.exe" ...
```

---

### ❌ Issue 4: "Path too long" error

**Error message:**
```
The path exceeds 260 characters.
Target name: D:\...\very\deeply\nested\...\中文文件名.txt
```

**Cause:** Windows NTFS path limit of 260 characters (or 32,767 with Unicode long path support).

**Solutions:**

**Solution 1: Enable long path support (Windows 10 1607+)**

PowerShell (Admin):
```powershell
# Enable long path support
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
    -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force

# Restart Windows
Restart-Computer
```

OR manually:
```
1. Press Windows + R
2. Type: gpedit.msc
3. Navigate: Computer Configuration > Administrative Templates > System > Filesystem
4. Enable: "Enable Win32 long paths"
5. Restart
```

**Solution 2: Move directory to shorter path**
```powershell
# Move from:
#   C:\Users\MyUser\Documents\Projects\2024\Q1\Reports\Final\Chinese...
# To:
#   C:\Data\Chinese...
```

**Solution 3: Create shorter translations**
Modify `Sanitize-Filename` to create abbreviations:
```powershell
# For long names, abbreviate:
# 2024年第一季度财务报告 → 2024_Q1_Finance_Report
```

**Solution 4: Use shortened paths in parent folders**
```powershell
# Rename parent folders first to shorter English names
# Then run the script on the tree below
```

---

### ❌ Issue 5: Report not generated or empty

**Symptoms:**
- No `Arborescence_Translation_Report.md` file
- File exists but is empty or corrupted
- Audit CSV has headers only, no data

**Causes:**
1. Output directory doesn't exist or is read-only
2. Insufficient disk space
3. File permissions prevent creation
4. Script terminated early

**Diagnosis:**

```powershell
# Check output directory
Test-Path "D:\Reports"
Get-Item "D:\Reports" | Select-Object FullName, Attributes

# Check disk space
Get-PSDrive D | Select-Object Used, Free

# Check file permissions
Get-Acl "D:\Reports" | Format-List
```

**Solutions:**

**Solution 1: Verify output directory exists and is writable**
```powershell
# Create if missing
$outDir = "D:\Reports"
if (-not (Test-Path $outDir)) {
    New-Item -Path $outDir -ItemType Directory
}

# Verify write permission
Test-Path $outDir -PathType Container  # Should return $true
```

**Solution 2: Use absolute paths**
```powershell
# Instead of:
.\script.ps1 -OutputDir ".\reports"

# Use:
.\script.ps1 -OutputDir "D:\Reports"
```

**Solution 3: Check disk space**
```powershell
# Free up space if needed
Get-PSDrive | Where-Object Free -lt 1GB  # Show drives with < 1GB free
```

**Solution 4: Run in WhatIf mode to test**
```powershell
.\script.ps1 -RootPath "D:\Data" -OutputDir "D:\Reports" -WhatIf -Verbose
# -Verbose shows more detail
```

---

### ❌ Issue 6: Rename operations failed (audit log shows "Failed")

**Symptoms:**
- Audit CSV shows `Status: Failed` for multiple items
- Files/folders not actually renamed on disk
- Directory structure unchanged after script completes

**Common failure messages:**
- `Target already exists: D:\Data\Project`
- `Error: Access denied`
- `Path is not valid`
- `Name already exists`

**Analysis:**

```powershell
# Check the audit CSV for patterns
Import-Csv "Rename_Audit_Log.csv" | 
    Where-Object Status -eq "Failed" | 
    Select-Object OriginalName, Message | 
    Format-Table -AutoSize
```

**Solutions by cause:**

**Cause 1: Duplicate translations**
```
Message: "Target already exists"
```

Two different Chinese names translated to the same English name:
```
项目文件夹 → Project_Folder
项目文件  → Project_Folder  (conflict!)
```

**Solution:**
- Modify one name manually before running script
- Or implement custom translation dictionary with unique names

**Cause 2: Permission denied**
```
Message: "Access denied" or "Error: Access to the path is denied"
```

**Solution:** (See Issue 3 above)

**Cause 3: File in use**
```
Message: "File in use by another process" or "Locked"
```

**Solution:**
- Close all applications using the directory
- Restart Windows if necessary
- Try again

**Cause 4: Path validation failed**
```
Message: "Invalid characters in path" or "Path too long"
```

**Solution:**
- Check filename for invalid characters: `< > : " / \ | ? *`
- Shorten path (see Issue 4)

---

## Frequently Asked Questions

### Q1: Can I undo a rename operation?

**Answer:** Yes, use the audit log CSV.

**Method 1: Automated reverse script**
```powershell
# Create reverse-rename script from audit log
$audit = Import-Csv "Rename_Audit_Log.csv" | 
    Where-Object Status -eq "Success"

foreach ($item in $audit) {
    $oldPath = $item.OriginalPath
    $newName = $item.OriginalName
    
    # Reverse rename: NewPath → OldName
    Rename-Item -Path $oldPath -NewName $newName -Verbose
}
```

**Method 2: Windows File History (if enabled)**
```powershell
# Restore previous version via Windows File History
# File Explorer → Right-click folder → "Restore previous versions"
```

**Method 3: Manual restore from backup**
```powershell
Copy-Item -Path "D:\Data_Backup_20240620_104530" -Destination "D:\Data" -Recurse
```

---

### Q2: Can the script handle symbolic links or junctions?

**Answer:** Partially.

**Current behavior:**
- Detects the link as a folder/file
- Attempts to rename the link itself (not the target)
- May fail if target is on different drive

**Recommended:**
- Avoid running on directories containing symlinks
- Or use `-SkipRename` mode to preview only
- Manually handle symlinks separately

---

### Q3: What languages can be translated?

**Current:** Simplified Chinese (zh-CN) → English

**To support other languages:**

Modify `Invoke-GoogleTranslation`:
```powershell
$url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=ja&tl=en&dt=t&q=$encodedText"
#                                                                        ↑
#                                                            Change language code
```

**Common language codes:**
- `zh-CN` — Simplified Chinese
- `zh-TW` — Traditional Chinese
- `ja` — Japanese
- `ko` — Korean
- `es` — Spanish
- `fr` — French
- `de` — German

---

### Q4: Can I use this script on network shares?

**Answer:** Yes, with caveats.

**Supported:** UNC paths like `\\server\share\folder`

**Considerations:**
- Performance depends on network latency
- May timeout on slow/unstable connections
- Rename operations may fail due to network delays
- Audit trail will be on local machine

**Recommendation:**
```powershell
# For network shares, use longer timeout and fewer retries
.\script.ps1 `
    -RootPath "\\server\share\folder" `
    -MaxTranslationRetries 1 `
    -WhatIf  # Preview first
```

---

### Q5: Does the script modify file contents?

**Answer:** No. Only filenames and folder names are changed.

File contents, timestamps, permissions remain unchanged.

---

### Q6: Can I run multiple instances of the script simultaneously?

**Answer:** Not recommended.

**Risk:** Multiple script instances rename items in the same directory, causing:
- Conflicts (both trying to rename the same file)
- Audit log inconsistency
- Partial failures

**Recommendation:** Use serialized execution:
```powershell
# Run scripts in sequence, not parallel
.\script.ps1 -RootPath "D:\Folder1"
.\script.ps1 -RootPath "D:\Folder2"
```

---

### Q7: What's the maximum directory size supported?

**Answer:** No hard limit, but practical constraints:

| Size | Time | Memory | Status |
|------|------|--------|--------|
| 1,000 items | <1 sec | <10MB | ✅ Fast |
| 10,000 items | 5-10 sec | 50MB | ✅ Good |
| 100,000 items | 1-2 min | 500MB | ⚠️ Slow |
| 1,000,000 items | 10+ min | 5GB+ | ❌ Not recommended |

**Bottleneck:** Translation API (5-second timeout per unique Chinese string).

**Optimization:** Use `SkipTranslation` for large directories with few Chinese items.

---

### Q8: How do I exclude certain directories?

**Answer:** Edit the script's `$noiseDirPatterns` array.

**Current list:**
```powershell
$noiseDirPatterns = @(
    'node_modules', '.git', '.svn',
    '__pycache__', '.pytest_cache',
    'dist', 'build', '.vscode',
    ...
)
```

**To exclude `Archive` folder:**
```powershell
$noiseDirPatterns += 'Archive'
```

These folders will be collapsed and not recursed.

---

### Q9: Can I use a custom translation service instead of Google?

**Answer:** Yes, with code modification.

**Steps:**
1. Add new service function
2. Update `Get-ChineseTranslation` switch statement
3. Pass service name via `-TranslationService` parameter

**Example for Microsoft Translator:**
```powershell
function Invoke-MicrosoftTranslation {
    param([string]$Text)
    
    $headers = @{
        "Ocp-Apim-Subscription-Key" = $env:AZURE_TRANSLATOR_KEY
    }
    $body = @(@{"Text" = $Text})
    
    $response = Invoke-WebRequest `
        -Method Post `
        -Uri "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=zh-Hans&to=en" `
        -Headers $headers `
        -Body ($body | ConvertTo-Json) `
        -ContentType "application/json"
    
    return ($response.Content | ConvertFrom-Json)[0].translations[0].text
}

# Then in Get-ChineseTranslation:
"MicrosoftTranslator" {
    $translation = Invoke-MicrosoftTranslation -Text $Text
}
```

---

### Q10: Is there a GUI version?

**Answer:** Not currently included.

**Workaround:**

Create a simple HTML/JavaScript interface:
```html
<html>
<body>
<input id="path" type="text" placeholder="Directory path">
<button onclick="runScript()">Translate</button>
<script>
function runScript() {
    const path = document.getElementById('path').value;
    // Call PowerShell script via API endpoint
    fetch('/api/translate', {method: 'POST', body: JSON.stringify({path})})
}
</script>
</body>
</html>
```

Or use Windows Forms wrapper in PowerShell.

---

## Advanced Troubleshooting

### Scenario: Script crashes or stops unexpectedly

**Diagnosis steps:**

```powershell
# 1. Run with verbose output
.\script.ps1 -RootPath "D:\Data" -Verbose

# 2. Capture full error
$ErrorActionPreference = "Stop"  # Don't suppress errors
.\script.ps1 -RootPath "D:\Data"

# 3. Enable script debugging
Set-PSDebug -Trace 1
.\script.ps1 -RootPath "D:\Data"
```

**Common crash points:**
1. Unicode character in translation (encoding issue)
2. Out of memory (too many items)
3. Network timeout (unhandled exception in API call)
4. Filesystem error (drive disconnected)

---

### Scenario: Translations look nonsensical

**Example output:**
```
项目 → project
文档 → documentation
说明 → instruction
(Good so far)

but:
某些特殊术语 → some special terms  (generic)
内部流程 → internal procedures    (vague)
```

**Cause:** Machine translation without domain context.

**Solutions:**

1. **Create custom dictionary for domain terms:**
```json
{
  "某些特殊术语": "CompanySpecificTerm",
  "内部流程": "InternalWorkflow"
}
```

2. **Review and manually correct** translation cache before running actual rename

3. **Use service with better accuracy** (paid options like DeepL)

---

### Scenario: Performance degradation over time

**Symptoms:**
- Script slows down as it processes more items
- Memory usage increases

**Diagnosis:**

```powershell
# Monitor memory during execution
$process = Get-Process powershell
while ($true) {
    Write-Host "Memory: $($process.WorkingSet / 1MB) MB"
    Start-Sleep 1
}
```

**Common causes:**
1. Translation cache growing (each unique Chinese string added)
2. Rename log accumulating (one entry per operation)
3. Tree lines buffer filling (one line per item)

**Mitigation:**
- For very large directories, process in batches:
```powershell
$subdirs = Get-ChildItem -Path "D:\Data" -Directory
foreach ($subdir in $subdirs) {
    .\script.ps1 -RootPath $subdir.FullName
}
```

---

## Recovery Procedures

### Full Recovery After Failed Rename

**Step 1: Identify all failed operations**
```powershell
$failedOps = Import-Csv "Rename_Audit_Log.csv" | 
    Where-Object Status -eq "Failed"
$failedOps | Export-Csv "Failed_Operations.csv"
```

**Step 2: Analyze failure reasons**
```powershell
$failedOps | 
    Select-Object OriginalName, Message | 
    Group-Object Message
```

**Step 3: Resolve root causes**
- Permission issues → run as admin
- File locks → close applications
- Path conflicts → rename conflicting items manually

**Step 4: Retry operation**
```powershell
# Modify script to retry only failed items
# Or manually rename using:
foreach ($item in $failedOps) {
    Rename-Item -Path $item.OriginalPath -NewName $item.Translation
}
```

---

### Restore from Backup

```powershell
# If everything goes wrong:
Remove-Item -Path "D:\Data" -Recurse -Force
Copy-Item -Path "D:\Data_Backup" -Destination "D:\Data" -Recurse
```

---

## Performance Optimization

### For Large Directories

**Tip 1: Use `-SkipTranslation` if translations are already prepared**
```powershell
# If you have a translations.json prepared:
.\script.ps1 -RootPath "D:\Data" -SkipTranslation  # Faster
```

**Tip 2: Process in batches**
```powershell
$dirs = Get-ChildItem "D:\Data" -Directory
$dirs | ForEach-Object {
    .\script.ps1 -RootPath $_.FullName -OutputDir "D:\Reports\$($_.Name)"
}
```

**Tip 3: Run with `-WhatIf` first (no renaming)**
```powershell
# Much faster, preview all changes:
.\script.ps1 -RootPath "D:\Data" -WhatIf
```

**Tip 4: Reduce network timeout**
```powershell
# Faster failure if API unreachable:
.\script.ps1 -RootPath "D:\Data" -MaxTranslationRetries 1
```

---

## Known Limitations

### 1. Chinese Detection

**Limitation:** Only detects specific Unicode ranges.

**What's covered:** Simplified Chinese (99% of common characters)

**What's not:** Variants, punctuation, mixed scripts

**Workaround:** Modify `Test-ContainsChinese` regex

---

### 2. Translation Quality

**Limitation:** Google Translate is general-purpose, not domain-aware.

**Result:** Technical terms may be translated generically

**Workaround:** Use custom translation dictionary for domain terms

---

### 3. Path Length Limit

**Limitation:** Windows NTFS has 260-character path limit (without long path support)

**Symptom:** Error when total path exceeds 260 chars

**Workaround:** Enable long path support or move to shorter paths

---

### 4. File Locking

**Limitation:** Can't rename files in use by other processes

**Symptom:** "File in use" error

**Workaround:** Close other applications or restart Windows

---

### 5. Special Characters

**Limitation:** Some characters in translations may be invalid on filesystems

**Examples:** `< > : " / \ | ? *` invalid on Windows

**Handling:** Script replaces these with underscores

---

### 6. Network Reliability

**Limitation:** Depends on Google Translate API availability

**Risk:** API downtime = no translations

**Workaround:** Use offline fallback service

---

*For additional support or unreported issues, consult the main documentation or the script's inline comments.*
