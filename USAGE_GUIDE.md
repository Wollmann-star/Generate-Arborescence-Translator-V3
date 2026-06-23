# Generate-Arborescence-Translator-V3 — User Guide

## Overview

**Generate-Arborescence-Translator-V3.ps1** is an enterprise-grade PowerShell script that automatically detects Chinese characters in folder and file names, translates them to English, and safely renames items in the filesystem while maintaining a complete audit trail.

This script extends the functionality of **Generate-Arborescence-View-V2.ps1** by adding:
- ✅ Automatic Chinese-to-English translation
- ✅ Safe filesystem renaming (depth-first strategy to prevent path conflicts)
- ✅ Detailed audit logging and reporting
- ✅ WhatIf simulation mode for safe previewing
- ✅ Comprehensive before/after directory tree comparison

---

## System Requirements

- **Windows 10 or later** (tested on Windows 10 & Windows 11)
- **PowerShell 5.1 or later** (PowerShell 7+ recommended for better performance)
- **Network access** (if using Google Translate service for translation)
- **Write permissions** to the target directory (for actual renaming; not required for WhatIf mode)

---

## Quick Start

### Basic Usage

```powershell
# Scan current directory with WhatIf preview (no actual changes)
.\Generate-Arborescence-Translator-V3.ps1 -WhatIf

# Scan a specific directory (with actual renaming)
.\Generate-Arborescence-Translator-V3.ps1 -RootPath "D:\MyData"

# Use alternative output directory
.\Generate-Arborescence-Translator-V3.ps1 -RootPath "C:\Projects" -OutputDir "D:\Reports"
```

---

## Parameter Reference

### `-RootPath` (string)
**Default:** `"."`

The directory to scan for Chinese characters. Defaults to the current working directory. Accepts:
- Relative paths: `".\subfolder"`
- Absolute paths: `"C:\Data\MyProject"`
- Network paths: `"\\server\share\folder"`

### `-OutputDir` (string)
**Default:** `"."`

Directory where the generated reports will be saved:
- Markdown report: `Arborescence_Translation_Report.md`
- Audit CSV: `Rename_Audit_Log.csv`

### `-WhatIf` (switch)
**Default:** `$false`

Enables **simulation mode**. When set, the script will:
- Preview all proposed renames
- Generate full reports
- **NOT** perform actual filesystem changes

**Always run with `-WhatIf` first to preview changes!**

### `-SkipTranslation` (switch)
**Default:** `$false`

Skips the translation process. Useful for:
- Testing the scanning/detection logic
- When you only want to see which items contain Chinese characters
- Dry-run scenarios

### `-SkipRename` (switch)
**Default:** `$false`

Skips the renaming operations. Useful when you want to:
- Only generate the detection report
- Review proposed translations without making changes

### `-TranslationService` (string)
**Default:** `"GoogleTranslate"`

Specifies the translation backend:
- `"GoogleTranslate"` — Uses Google Translate free API (no authentication required)
- `"Manual"` — Returns Chinese name with `[TRANS]` prefix (for testing)

### `-MaxTranslationRetries` (int)
**Default:** `3`

Number of retry attempts for translation API calls if the initial request fails. Improves reliability in low-bandwidth or unstable network conditions.

---

## Usage Examples

### Example 1: Safe Preview Before Making Changes

```powershell
# First run: Preview what will be renamed
.\Generate-Arborescence-Translator-V3.ps1 `
    -RootPath "D:\MyData" `
    -OutputDir "D:\Reports" `
    -WhatIf

# Review the generated report: D:\Reports\Arborescence_Translation_Report.md
# Review the audit log: D:\Reports\Rename_Audit_Log.csv

# If satisfied, run again without -WhatIf to perform actual renaming
```

### Example 2: Scan with Actual Renaming

```powershell
# Execute the renaming operation
.\Generate-Arborescence-Translator-V3.ps1 `
    -RootPath "C:\Projects" `
    -OutputDir "C:\Projects\Reports" `
    -TranslationService GoogleTranslate
```

### Example 3: Detection Only (No Translation)

```powershell
# Only detect Chinese characters, don't translate or rename
.\Generate-Arborescence-Translator-V3.ps1 `
    -RootPath "E:\Archive" `
    -SkipTranslation `
    -SkipRename
```

### Example 4: Manual Testing with Fallback Service

```powershell
# Test with manual translation (appends [TRANS] prefix)
.\Generate-Arborescence-Translator-V3.ps1 `
    -RootPath "D:\TestFolder" `
    -TranslationService Manual `
    -WhatIf
```

---

## Output Files

The script generates three output files in the specified output directory:

### 1. **Arborescence_Translation_Report.md** (Main Report)

Comprehensive markdown report containing:

| Section | Content |
|---------|---------|
| **Metadata** | Scan date, root directory, item counts, WhatIf status |
| **Translation Cache** | Mapping of all Chinese → English translations |
| **Audit Log** | Detailed table of each rename operation with status |
| **BEFORE Tree** | Complete directory structure before renaming (with 🔤 markers for Chinese items) |
| **AFTER Tree** | Complete directory structure after renaming |
| **Conventions** | Reading guide for interpreting the report |
| **Summary** | Statistics and execution details |

**Usage:** Open in any Markdown viewer (VS Code, GitHub, GitLab, Notepad++) to see syntax-highlighted trees with color-coded items.

### 2. **Rename_Audit_Log.csv** (Audit Trail)

Spreadsheet-compatible CSV file with columns:

| Column | Description |
|--------|-------------|
| **OriginalPath** | Full filesystem path before rename |
| **OriginalName** | Filename/folder name before rename |
| **Translation** | English translation applied |
| **ItemType** | "Folder" or "File" |
| **Status** | "Success" or "Failed" |
| **Message** | Detailed outcome message |
| **Timestamp** | When the operation was attempted |

**Usage:** Open in Excel, Google Sheets, or any CSV reader for detailed audit trail. Filter by `Status` column to identify any failed operations.

### 3. **Standard Output (Console)**

The script prints colored console output during execution:
- 🟢 Green: Successful operations
- 🟡 Yellow: Warnings / informational messages
- 🔴 Red: Errors / failed operations
- 🟣 Magenta: Items containing Chinese characters
- 🔵 Blue: WhatIf simulation messages

---

## Understanding the Report

### Directory Tree Format

The trees use **diff-style syntax highlighting** (no actual diff intended—just for visual distinction):

```diff
@@ D:\MyData @@
+ ├── 📁 项目文件夹/ 🔤
  │   ├── 📋 config.json
  │   └── 📝 说明.md 🔤
  └── 📁 归档/
      └── 📕 2024年报告.pdf 🔤
```

**Reading guide:**
- `+ ` = Expanded folder (shown in green)
- `- ` = Collapsed dependency folder (shown in red)
- `  ` = Regular file (neutral)
- `🔤` = Item contains Chinese characters
- `/` after name = Directory
- Extension visible = File

### Translation Cache

Shows all detected Chinese strings and their translations:

| Chinese | English |
|---------|---------|
| `项目文件夹` | `Project_Folder` |
| `说明` | `Instructions` |
| `归档` | `Archive` |
| `2024年报告` | `2024_Annual_Report` |

**Note:** Translations are sanitized for filesystem safety:
- Invalid characters are replaced with underscores
- Leading/trailing spaces are trimmed
- Multiple spaces become single spaces

### Rename Operations

Each row in the audit table represents one attempted operation:

```
| 项目文件夹 | Project_Folder | Folder | Success | Successfully renamed to: ... | 2024-06-20 10:45:30 |
| 说明.md   | Instructions.md | File   | Failed  | Target already exists: ... | 2024-06-20 10:45:31 |
```

**Failure causes:**
- **Target already exists:** A file/folder with the translated name already exists
- **Permission denied:** Insufficient write permissions to the target directory
- **Invalid path:** Path length exceeds Windows limit (260 chars) or contains invalid characters
- **In use:** File is locked by another process

---

## Safety Features & Best Practices

### Depth-First Renaming (Bottom-Up Strategy)

The script renames items starting from the deepest nested items first:

```
Before:
  项目/             ← renamed last (after children are renamed)
    ├── 文档/       ← renamed second
    │   └── 说明.md ← renamed first
    └── 代码/       ← renamed third
```

This strategy prevents path conflicts where a parent folder rename would make child paths invalid.

### Conflict Detection

The script automatically detects and prevents:
- **Duplicate translations:** Two items that would have identical translations
- **Target already exists:** Refusing to overwrite existing files/folders
- **Invalid characters:** Sanitizing names to be filesystem-safe

### WhatIf Simulation

**Always run with `-WhatIf` first:**

```powershell
# Step 1: Preview all changes
.\Generate-Arborescence-Translator-V3.ps1 -RootPath "D:\Data" -WhatIf

# Step 2: Review the report
# Review Arborescence_Translation_Report.md
# Check for any concerning translations

# Step 3: Execute only if satisfied
.\Generate-Arborescence-Translator-V3.ps1 -RootPath "D:\Data"
```

### Backup Recommendation

Before executing actual renames on important data:

```powershell
# Create a backup of the entire directory tree
Copy-Item -Path "D:\Data" -Destination "D:\Data_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -Recurse
```

---

## Troubleshooting

### Issue: Translation Service Fails

**Symptoms:**
- Slow execution
- Items not translated (fallback to original names)
- Network timeout errors

**Solutions:**
1. Check internet connectivity:
   ```powershell
   Invoke-WebRequest -Uri "https://www.google.com" -TimeoutSec 5
   ```

2. Increase retry attempts:
   ```powershell
   .\Generate-Arborescence-Translator-V3.ps1 -MaxTranslationRetries 5
   ```

3. Fall back to manual translation for testing:
   ```powershell
   .\Generate-Arborescence-Translator-V3.ps1 -TranslationService Manual -WhatIf
   ```

### Issue: Rename Operations Fail

**Symptoms:**
- Audit log shows "Failed" status
- Files/folders not renamed on disk

**Common causes:**
1. **Insufficient permissions:** Run PowerShell as Administrator
   ```powershell
   # Right-click PowerShell → "Run as Administrator"
   ```

2. **File locked by another process:** Close all applications accessing the directory
   - Check Windows Explorer
   - Check antivirus/backup software
   - Close IDE or code editor

3. **Path too long:** Windows has 260-character path limit
   - **Solution:** Move the directory to a shorter path first

4. **Insufficient disk space:** Check available space
   ```powershell
   Get-PSDrive C | Select-Object Used, Free
   ```

### Issue: Translations Look Wrong

**Symptoms:**
- Garbled or nonsensical English names
- Names not matching expected translations

**Causes:**
- Machine translation limitations (especially for domain-specific terms)
- Ambiguous Chinese (context-dependent meanings)
- Abbreviated or informal Chinese

**Solutions:**
1. Review the translation cache in the report
2. Manually verify translations before actual renaming
3. Correct names after script completion using file explorer or a second rename script

### Issue: Script Hangs

**Symptoms:**
- No progress for several minutes
- Process not responsive

**Likely cause:** Network timeout waiting for translation service

**Solution:** Press `Ctrl+C` to cancel, then:
```powershell
# Try again with fallback service
.\Generate-Arborescence-Translator-V3.ps1 -TranslationService Manual
```

---

## Advanced Usage

### Batch Processing Multiple Directories

```powershell
$directories = @("D:\Proj1", "D:\Proj2", "D:\Proj3")

foreach ($dir in $directories) {
    Write-Host "Processing: $dir" -ForegroundColor Cyan
    .\Generate-Arborescence-Translator-V3.ps1 `
        -RootPath $dir `
        -OutputDir "$dir\Reports"
}
```

### Filtering Results for Review

After running with `-WhatIf`, filter the audit log to see only specific statuses:

```powershell
# PowerShell: Show only failed operations
Import-Csv "Rename_Audit_Log.csv" | Where-Object Status -eq "Failed"
```

### Comparing Before/After with External Tools

Export the tree structure to plain text for diff comparison:

```powershell
# After BEFORE and AFTER renames, compare
Compare-Object (Get-Content "Structure_BEFORE.txt") (Get-Content "Structure_AFTER.txt")
```

---

## FAQ

**Q: Can the script handle other languages besides Chinese?**
> Currently, the script is optimized for Simplified and Traditional Chinese. For other languages, you would need to modify the `Test-ContainsChinese` function to detect other character ranges.

**Q: What if translation produces duplicate names?**
> The script will log this as a failure in the audit trail and skip the duplicate rename. The original name is preserved.

**Q: Can I undo a rename operation?**
> The rename audit log contains both original and new names. You can manually create a reverse-rename script using the CSV, or use Windows File History if available.

**Q: Does the script modify file contents?**
> No. Only filenames and folder names are changed. File contents remain untouched.

**Q: Can I run this on network shares?**
> Yes, but performance will depend on network latency. Network paths like `\\server\share` are fully supported.

**Q: What's the maximum directory depth supported?**
> No hard limit, but performance degrades with very deep hierarchies (1000+ levels). Windows path limit is 260 characters.

---

## Support & Feedback

If you encounter issues or have suggestions:

1. **Check this guide** for troubleshooting
2. **Review the audit log** for detailed error messages
3. **Verify prerequisites** (PowerShell version, permissions, network)
4. **Run with WhatIf first** to isolate issues

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| V3 | 2024-06-20 | Initial release: Translation + safe renaming with audit trail |
| V2 | 2024-06-15 | Original arborescence scanner (repo branch) |

---

*For the latest version and updates, refer to your organization's documentation repository.*
