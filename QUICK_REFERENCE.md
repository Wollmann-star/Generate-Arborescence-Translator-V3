# Quick Reference Card — Generate-Arborescence-Translator-V3

## Command Template

```powershell
.\Generate-Arborescence-Translator-V3.ps1 -RootPath <path> -OutputDir <path> -WhatIf -SkipTranslation -SkipRename
```

---

## Most Common Commands

### Preview Changes (Safe, No Actual Changes)
```powershell
.\Generate-Arborescence-Translator-V3.ps1 -RootPath "D:\MyData" -WhatIf
```

### Execute with Actual Renaming
```powershell
.\Generate-Arborescence-Translator-V3.ps1 -RootPath "D:\MyData"
```

### Detect Chinese Only (No Translation)
```powershell
.\Generate-Arborescence-Translator-V3.ps1 -RootPath "D:\MyData" -SkipTranslation
```

### Custom Output Directory
```powershell
.\Generate-Arborescence-Translator-V3.ps1 -RootPath "C:\Data" -OutputDir "D:\Reports"
```

---

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-RootPath` | string | `.` | Directory to scan |
| `-OutputDir` | string | `.` | Where to save reports |
| `-WhatIf` | switch | — | Preview only, no changes |
| `-SkipTranslation` | switch | — | Detect only, no translation |
| `-SkipRename` | switch | — | Report only, no renaming |
| `-TranslationService` | string | `GoogleTranslate` | `GoogleTranslate` or `Manual` |
| `-MaxTranslationRetries` | int | `3` | Retry attempts for API calls |

---

## Output Files

| File | Purpose |
|------|---------|
| `Arborescence_Translation_Report.md` | Main report (BEFORE/AFTER trees + audit) |
| `Rename_Audit_Log.csv` | Spreadsheet with operation details |
| Console output | Real-time progress with color codes |

---

## Report Symbols

| Symbol | Meaning |
|--------|---------|
| `+` prefix | Expanded folder (green) |
| `-` prefix | Collapsed folder (red) |
| `🔤` | Contains Chinese characters |
| `✅` | Success |
| `❌` | Failed |
| `🔍` | WhatIf simulation |

---

## Typical Workflow

```
1. .\script.ps1 -RootPath "D:\Data" -WhatIf          ← Preview
2. Review: Arborescence_Translation_Report.md        ← Check translations
3. .\script.ps1 -RootPath "D:\Data"                 ← Execute
4. Review: Rename_Audit_Log.csv                      ← Verify success
```

---

## Troubleshooting at a Glance

| Problem | Quick Fix |
|---------|-----------|
| **Translation slow** | Run with `-WhatIf` first, use `-MaxTranslationRetries 1` |
| **Rename failed** | Run as Administrator, close locked files |
| **Path too long** | Move to shorter path, or split directory |
| **Wrong translations** | Use `-SkipTranslation` to review detection |
| **Script hangs** | Press Ctrl+C, try `-TranslationService Manual` |

---

## Unicode Ranges Detected

- **CJK Unified Ideographs:** U+4E00–U+9FFF (most common)
- **CJK Ext. A:** U+3400–U+4DBF (extended)
- **CJK Compatibility:** U+F900–U+FAFF (compatibility forms)

---

## Safety Checklist

Before running WITHOUT `-WhatIf`:

- [ ] Created backup of directory
- [ ] Ran with `-WhatIf` and reviewed changes
- [ ] PowerShell running as Administrator
- [ ] No applications locking files in directory
- [ ] Verified translation quality in report
- [ ] Output directory has write permissions

---

## Examples by Use Case

### Localization Project
```powershell
# Prepare Chinese-named project for English distribution
.\script.ps1 -RootPath "C:\MyProject" -OutputDir "C:\MyProject\QA" -WhatIf
```

### Archive Organization
```powershell
# Standardize old archive with mixed languages
.\script.ps1 -RootPath "\\Archive\2023" -MaxTranslationRetries 5
```

### Data Migration
```powershell
# Before moving to new system, translate all names
.\script.ps1 -RootPath "D:\LegacyData" -OutputDir "D:\Migration_Reports"
```

### Audit & Compliance
```powershell
# Create audit trail of all name changes
.\script.ps1 -RootPath "E:\ComplianceDir" -SkipRename  # Report only
```

---

## Keyboard Shortcuts

| Action | Key |
|--------|-----|
| Cancel running script | `Ctrl + C` |
| Clear console | `Clear-Host` or `cls` |
| Copy from console | `Ctrl + A` → `Ctrl + C` |

---

## Next Steps

1. **Read the full guide:** `USAGE_GUIDE.md`
2. **Review script comments:** Open `.ps1` file in VS Code
3. **Test safely:** Always use `-WhatIf` first
4. **Check audit trail:** Review `.csv` output for details

---

*Last updated: 2024-06-20*
