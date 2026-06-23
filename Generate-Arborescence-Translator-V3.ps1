# ============================================================
# Generate-Arborescence-Translator-V3.ps1
# 
# Enhanced arborescence script with automatic Chinese-to-English
# translation and safe filesystem renaming capabilities.
#
# Features:
#   - Scans directory tree (retains original V2 scanning logic)
#   - Detects Chinese characters in folder/file names
#   - Translates Chinese names to English automatically
#   - Safely renames items in filesystem (deepest-first strategy)
#   - Generates before/after directory reports
#   - Maintains detailed audit log of all operations
#   - Provides WhatIf simulation mode for preview
#
# Color coding (repurposed `diff` syntax highlighting):
#   @@ ... @@   -> root directory anchor      (header / meta)
#   +  prefix   -> expanded folder            (green)
#   -  prefix   -> collapsed dependency/build folder (red)
#      prefix   -> file                       (neutral)
#
# ============================================================

param(
    [string]$RootPath = ".",
    [string]$OutputDir = ".",
    [switch]$WhatIf = $false,
    [switch]$SkipTranslation = $false,
    [switch]$SkipRename = $false,
    [switch]$FilesOnly = $false,  # If set, only rename files (skip folders)
    [string]$TranslationService = "GoogleTranslate",  # GoogleTranslate or Manual (for testing)
    [int]$MaxTranslationRetries = 3
)

# ── 1. Configuration ────────────────────────────────────────
$outputReportFile   = "Arborescence_Translation_Report.md"
$outputAuditFile    = "Rename_Audit_Log.csv"
$outputBefore       = "Structure_BEFORE.txt"
$outputAfter        = "Structure_AFTER.txt"
$encoding           = [System.Text.UTF8Encoding]::new($false)  # UTF-8 without BOM

# Folders to collapse (same as V2)
$collapseNoiseDirs  = $true
$noiseDirPatterns   = @(
    'node_modules', '.git', '.svn', '.hg',
    '__pycache__', '.pytest_cache', '.mypy_cache',
    '.venv', 'venv', 'env',
    'dist', 'build', 'bin', 'obj', 'target',
    '.next', '.nuxt', '.idea', '.vs', '.vscode',
    'coverage', '.terraform', 'vendor', '.cache'
)

# Logging and timing
$startTime          = Get-Date
$scanDate           = $startTime.ToString("yyyy-MM-dd HH:mm:ss")
$script:logEntries  = [System.Collections.Generic.List[object]]::new()
$script:renameLog   = [System.Collections.Generic.List[object]]::new()
$script:translationCache = @{}  # In-memory cache for translations

# ── 2. Chinese Character Detection ──────────────────────────
function Test-ContainsChinese {
    <#
    .SYNOPSIS
    Detects if a string contains Chinese characters (CJK Unified Ideographs).
    
    .PARAMETER Text
    The string to test.
    
    .RETURNS
    $true if Chinese characters are found; $false otherwise.
    #>
    param([string]$Text)
    
    # CJK Unicode ranges: \u4E00-\u9FFF (common Chinese characters)
    # Also includes some extended ranges for completeness
    return $Text -match '[\u4E00-\u9FFF\u3400-\u4DBF\uF900-\uFAFF]'
}

# ── 3. Translation Function ────────────────────────────────
function Get-ChineseTranslation {
    <#
    .SYNOPSIS
    Translates a Chinese string to English using the configured service.
    
    .PARAMETER Text
    The Chinese text to translate.
    
    .PARAMETER Service
    Translation service: "GoogleTranslate" or "Manual".
    
    .RETURNS
    Translated English string, or original text if translation fails.
    #>
    param(
        [string]$Text,
        [string]$Service = "GoogleTranslate"
    )
    
    # Check cache first
    if ($script:translationCache.ContainsKey($Text)) {
        Write-Host "  [CACHED] $Text → $($script:translationCache[$Text])" -ForegroundColor DarkCyan
        return $script:translationCache[$Text]
    }
    
    # Don't translate if no Chinese detected
    if (-not (Test-ContainsChinese -Text $Text)) {
        $script:translationCache[$Text] = $Text
        return $Text
    }
    
    $translation = $null
    
    switch ($Service) {
        "GoogleTranslate" {
            $translation = Invoke-GoogleTranslation -Text $Text
        }
        "Manual" {
            # Fallback: returns original with [MANUAL] prefix
            $translation = "[TRANS] $Text"
        }
        default {
            $translation = $Text
        }
    }
    
    # Cache the result
    if ($translation) {
        $script:translationCache[$Text] = $translation
        Write-Host "  [TRANSLATED] $Text → $translation" -ForegroundColor Cyan
    } else {
        $script:translationCache[$Text] = $Text
        Write-Host "  [FAILED] $Text (fallback to original)" -ForegroundColor Yellow
        $translation = $Text
    }
    
    return $translation
}

# ── 4. Google Translate Integration ─────────────────────────
function Invoke-GoogleTranslation {
    <#
    .SYNOPSIS
    Uses Google Translate API via REST to translate text.
    Implements retry logic and error handling.
    
    .PARAMETER Text
    Text to translate (Chinese).
    
    .RETURNS
    Translated English text, or $null on failure.
    #>
    param([string]$Text)
    
    $maxRetries = $MaxTranslationRetries
    $retryCount = 0
    $translated = $null
    
    while ($retryCount -lt $maxRetries) {
        try {
            # Using Google Translate free API endpoint (no auth required)
            # Format: https://translate.googleapis.com/translate_a/element.js?
            # Simpler approach: use a public translation endpoint
            
            $encodedText = [System.Uri]::EscapeDataString($Text)
            $url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=zh-CN&tl=en&dt=t&q=$encodedText"
            
            # Timeout and error handling
            $response = Invoke-WebRequest -Uri $url -TimeoutSec 5 -ErrorAction Stop -UserAgent "Mozilla/5.0"
            
            # Parse response: returns JSON-like array structure
            # We need to extract the translated text from the response
            $content = $response.Content
            
            # Simple regex extraction for translation result
            # Google's response format: [[[translated_text, original_text, null, null, 0]...
            if ($content -match '\[\[\["([^"]+)"') {
                $translated = $matches[1]
                break
            }
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "    Retry $retryCount/$maxRetries..." -ForegroundColor Gray
                Start-Sleep -Seconds 1
            }
        }
    }
    
    return $translated
}

# ── 5. File/Folder Name Sanitization ─────────────────────────
function Sanitize-Filename {
    <#
    .SYNOPSIS
    Makes a translated name safe for use as a filesystem filename.
    Removes/replaces invalid characters, handles duplicates.
    
    .PARAMETER Name
    Original or translated name.
    
    .RETURNS
    Sanitized filename safe for Windows/Linux filesystems.
    #>
    param([string]$Name)
    
    # Remove invalid characters
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $sanitized = $Name
    
    foreach ($char in $invalid) {
        $sanitized = $sanitized.Replace([string]$char, "_")
    }
    
    # Replace other problematic patterns
    $sanitized = $sanitized `
        -replace '\s+$', '' `
        -replace '^\s+', '' `
        -replace '\s{2,}', ' ' `
        -replace '\.+$', ''
    
    # Trim to reasonable length (Windows has 255 char limit per filename)
    if ($sanitized.Length -gt 200) {
        $sanitized = $sanitized.Substring(0, 200)
    }
    
    return $sanitized
}

# ── 6. File Icon Helper (from V2) ───────────────────────────
function Get-FileIcon {
    param([string]$ext)
    switch ($ext.ToLower()) {
        ".ps1"  { return "⚙️" }
        ".py"   { return "🐍" }
        ".js"   { return "🟨" }
        ".ts"   { return "🔷" }
        ".json" { return "📋" }
        ".md"   { return "📝" }
        ".html" { return "🌐" }
        ".css"  { return "🎨" }
        ".sql"  { return "🗄️" }
        ".csv"  { return "📗" }
        ".xls"  { return "📗" }
        ".xlsx" { return "📗" }
        ".xlsm" { return "📗" }
        ".txt"  { return "📄" }
        ".xml"  { return "🧩" }
        ".yml"  { return "⚙️" }
        ".yaml" { return "⚙️" }
        ".sh"   { return "🐚" }
        ".bat"  { return "🖥️" }
        ".zip"  { return "📦" }
        ".png"  { return "🖼️" }
        ".jpg"  { return "🖼️" }
        ".gif"  { return "🖼️" }
        ".svg"  { return "🖼️" }
        ".pdf"  { return "📕" }
        ".exe"  { return "⚡" }
        ".dll"  { return "🔩" }
        default { return "📄" }
    }
}

# ── 7. Recursive Tree Builder (BEFORE scanning) ─────────────
$script:treeLinesBefore    = [System.Collections.Generic.List[string]]::new()
$script:processedCount     = 0
$script:collapsedDirs      = 0
$script:collapsedItems     = 0
$script:itemsWithChinese   = 0

function Build-TreeBefore {
    <#
    .SYNOPSIS
    Recursively builds the directory tree BEFORE renaming.
    Uses original names and detects Chinese characters.
    #>
    param([string]$Path, [string]$Prefix = "")
    
    $items = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue |
             Sort-Object -Property @{Expression = 'PSIsContainer'; Descending = $true}, `
                                   @{Expression = 'Name'; Descending = $false}
    
    $total = $items.Count
    for ($i = 0; $i -lt $total; $i++) {
        $item      = $items[$i]
        $isLast    = ($i -eq $total - 1)
        $connector = if ($isLast) { "└── " } else { "├── " }
        $childPfx  = if ($isLast) { "    " } else { "│   " }
        
        $hasChinese = if (Test-ContainsChinese -Text $item.Name) { "🔤" } else { "" }
        
        if ($item.PSIsContainer) {
            $script:processedCount++
            
            if ($collapseNoiseDirs -and ($noiseDirPatterns -contains $item.Name)) {
                $inner        = Get-ChildItem -Path $item.FullName -Recurse -ErrorAction SilentlyContinue
                $innerFiles   = ($inner | Where-Object { -not $_.PSIsContainer }).Count
                $innerFolders = ($inner | Where-Object {  $_.PSIsContainer }).Count
                $script:collapsedDirs++
                $script:collapsedItems += ($innerFiles + $innerFolders)
                
                Write-Host "  Folder #$($script:processedCount): $($item.Name) [collapsed]" -ForegroundColor Red
                $script:treeLinesBefore.Add("- $Prefix$connector🚫 $($item.Name)/  ($innerFolders folders, $innerFiles files — collapsed)")
            } else {
                if (Test-ContainsChinese -Text $item.Name) {
                    $script:itemsWithChinese++
                    Write-Host "  Folder #$($script:processedCount): $($item.Name) $hasChinese" -ForegroundColor Magenta
                } else {
                    Write-Host "  Folder #$($script:processedCount): $($item.Name)" -ForegroundColor DarkGray
                }
                
                $script:treeLinesBefore.Add("+ $Prefix$connector📁 $($item.Name)/ $hasChinese")
                Build-TreeBefore -Path $item.FullName -Prefix "$Prefix$childPfx"
            }
        } else {
            $icon = Get-FileIcon -ext $item.Extension
            if (Test-ContainsChinese -Text $item.Name) {
                $script:itemsWithChinese++
                Write-Host "    File: $($item.Name) $hasChinese" -ForegroundColor Magenta
            }
            $script:treeLinesBefore.Add("  $Prefix$connector$icon $($item.Name) $hasChinese")
        }
    }
}

# ── 8. Rename Strategy: Depth-First Bottom-Up ───────────────
function Get-ItemsForRenaming {
    <#
    .SYNOPSIS
    Returns all items to be renamed, sorted in depth-first order
    (deepest items first) to avoid path conflicts.
    
    .PARAMETER RootPath
    The root directory to scan.
    
    .RETURNS
    Array of objects with: FullPath, OldName, NewName, ItemType, HasChinese
    #>
    param([string]$RootPath)
    
    $itemsToRename = @()
    
    # Get all items recursively
    $allItems = Get-ChildItem -Path $RootPath -Recurse -ErrorAction SilentlyContinue
    
    # Sort by depth (longest path first = deepest first)
    $allItems = $allItems | Sort-Object { ($_.FullName -split '([char][System.IO.Path]::DirectorySeparatorChar)').Count } -Descending
    
    foreach ($item in $allItems) {
        if (Test-ContainsChinese -Text $item.Name) {
            # Skip folders if FilesOnly mode is enabled
            if ($FilesOnly -and $item.PSIsContainer) {
                continue
            }
            
            # Get translation
            $translation = if ($SkipTranslation) { $item.Name } else { Get-ChineseTranslation -Text $item.Name }
            $translation = Sanitize-Filename -Name $translation
            
            # Only create rename entry if translation differs
            if ($translation -ne $item.Name) {
                $itemsToRename += @{
                    FullPath    = $item.FullName
                    ParentPath  = $item.Directory.FullName
                    OldName     = $item.Name
                    NewName     = $translation
                    ItemType    = if ($item.PSIsContainer) { "Folder" } else { "File" }
                    HasChinese  = $true
                    Depth       = ($item.FullName -split '([char][System.IO.Path]::DirectorySeparatorChar)').Count
                }
            }
        }
    }
    
    return $itemsToRename
}

# ── 9. Safe Rename Execution ────────────────────────────────
function Invoke-SafeRename {
    <#
    .SYNOPSIS
    Performs safe renaming with conflict detection and logging.
    
    .PARAMETER Item
    Object containing: FullPath, OldName, NewName, ItemType
    
    .PARAMETER WhatIfMode
    If true, simulates rename without actual changes.
    
    .RETURNS
    Status object with Success/Failed and message.
    #>
    param(
        [object]$Item,
        [bool]$WhatIfMode = $false
    )
    
    $status = @{
        OriginalPath = $Item.FullPath
        OriginalName = $Item.OldName
        NewName      = $Item.NewName
        ItemType     = $Item.ItemType
        Success      = $false
        Message      = ""
    }
    
    try {
        # Check if target already exists
        $targetPath = Join-Path $Item.ParentPath $Item.NewName
        if ((Test-Path -Path $targetPath) -and ($targetPath -ne $Item.FullPath)) {
            # Handle naming conflict by appending a unique suffix
            $baseName = $Item.NewName
            $extension = ""
            
            # For files, preserve the extension
            if ($Item.ItemType -eq "File") {
                $lastDotIndex = $Item.NewName.LastIndexOf('.')
                if ($lastDotIndex -gt 0) {
                    $baseName = $Item.NewName.Substring(0, $lastDotIndex)
                    $extension = $Item.NewName.Substring($lastDotIndex)
                }
            }
            
            # Generate unique name with counter
            $counter = 1
            do {
                $newNameWithSuffix = "${baseName}_${counter}${extension}"
                $targetPath = Join-Path $Item.ParentPath $newNameWithSuffix
                $counter++
            } while ((Test-Path -Path $targetPath) -and ($counter -lt 100))
            
            # Update the new name with the unique suffix
            $Item.NewName = $newNameWithSuffix
            $status.NewName = $newNameWithSuffix
            $status.Message = "Conflict resolved: renamed to $newNameWithSuffix"
            Write-Host "  ⚠️  CONFLICT RESOLVED: $($Item.OldName) → $($newNameWithSuffix)" -ForegroundColor Yellow
        }
        
        # Perform rename
        if ($WhatIfMode) {
            if (-not $status.Message) {
                $status.Message = "[SIMULATION] Would rename to: $targetPath"
            }
            Write-Host "  🔍 [WHATIF] $($Item.OldName) → $($Item.NewName)" -ForegroundColor Blue
            $status.Success = $true
        } else {
            Rename-Item -Path $Item.FullPath -NewName $Item.NewName -ErrorAction Stop
            if (-not $status.Message) {
                $status.Message = "Successfully renamed to: $targetPath"
            }
            Write-Host "  ✅ RENAMED: $($Item.OldName) → $($Item.NewName)" -ForegroundColor Green
            $status.Success = $true
        }
    }
    catch {
        $status.Message = "Error: $($_.Exception.Message)"
        Write-Host "  ❌ ERROR: $($Item.OldName) - $($status.Message)" -ForegroundColor Red
        $status.Success = $false
    }
    
    return $status
}

# ── 10. Main Execution Flow ─────────────────────────────────
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Generate-Arborescence-Translator-V3                      ║" -ForegroundColor Cyan
Write-Host "║  Chinese-to-English Translation & Filesystem Renaming     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Resolve paths
$rootResolved = (Resolve-Path $RootPath).Path
$outputDirResolved = (Resolve-Path $OutputDir).Path

Write-Host "📊 PHASE 1: SCANNING AND DETECTION" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────"
Write-Host "Root directory: $rootResolved" -ForegroundColor Gray
Write-Host "Scanning directory tree..." -ForegroundColor Gray

# Get initial totals
$allItems = Get-ChildItem -Path $rootResolved -Recurse -ErrorAction SilentlyContinue
$totalFiles = ($allItems | Where-Object { -not $_.PSIsContainer }).Count
$totalFolders = ($allItems | Where-Object { $_.PSIsContainer }).Count

Write-Host "  Total folders: $totalFolders" -ForegroundColor Gray
Write-Host "  Total files: $totalFiles" -ForegroundColor Gray

# Build BEFORE tree
Build-TreeBefore -Path $rootResolved

Write-Host ""
Write-Host "🔤 PHASE 2: CHINESE CHARACTER DETECTION" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────"
Write-Host "Items containing Chinese: $($script:itemsWithChinese)" -ForegroundColor Magenta

if ($script:itemsWithChinese -eq 0) {
    Write-Host "No Chinese characters detected. Exiting." -ForegroundColor Green
    exit 0
}

# Get items requiring translation
Write-Host ""
Write-Host "📝 PHASE 3: TRANSLATION" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────"

if ($SkipTranslation) {
    Write-Host "Translation skipped (SkipTranslation=$SkipTranslation)" -ForegroundColor Yellow
} else {
    Write-Host "Service: $TranslationService" -ForegroundColor Gray
    Write-Host "Translating detected items..." -ForegroundColor Gray
}

if ($FilesOnly) {
    Write-Host "Mode: Files Only (folders will not be renamed)" -ForegroundColor DarkCyan
} else {
    Write-Host "Mode: Files and Folders (full recursive renaming)" -ForegroundColor DarkCyan
}

$itemsToRename = Get-ItemsForRenaming -RootPath $rootResolved
Write-Host "Items ready for renaming: $($itemsToRename.Count)" -ForegroundColor Cyan

# Log translate cache
Write-Host ""
Write-Host "Translation Cache Summary:" -ForegroundColor DarkGray
$script:translationCache.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Key) → $($_.Value)" -ForegroundColor DarkGray
}

# Rename phase
Write-Host ""
Write-Host "♻️  PHASE 4: FILESYSTEM RENAMING" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────"

if ($WhatIf) {
    Write-Host "🔍 WHATIF MODE ENABLED - No actual changes will be made" -ForegroundColor Blue
}

$renameCount = 0
foreach ($item in $itemsToRename) {
    $status = Invoke-SafeRename -Item $item -WhatIfMode $WhatIf
    $renameCount++
    
    # Log entry
    $script:renameLog.Add(@{
        OriginalPath = $status.OriginalPath
        OriginalName = $status.OriginalName
        Translation  = $status.NewName
        ItemType     = $status.ItemType
        Status       = if ($status.Success) { "Success" } else { "Failed" }
        Message      = $status.Message
        Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    })
}

Write-Host ""
Write-Host "Rename operations completed: $renameCount" -ForegroundColor Cyan

# Rebuild tree AFTER renaming (if not in WhatIf mode)
Write-Host ""
Write-Host "📊 PHASE 5: POST-RENAME VERIFICATION" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────"

$script:treeLinesAfter = [System.Collections.Generic.List[string]]::new()
$script:processedCountAfter = 0

function Build-TreeAfter {
    param([string]$Path, [string]$Prefix = "")
    
    $items = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue |
             Sort-Object -Property @{Expression = 'PSIsContainer'; Descending = $true}, `
                                   @{Expression = 'Name'; Descending = $false}
    
    $total = $items.Count
    for ($i = 0; $i -lt $total; $i++) {
        $item      = $items[$i]
        $isLast    = ($i -eq $total - 1)
        $connector = if ($isLast) { "└── " } else { "├── " }
        $childPfx  = if ($isLast) { "    " } else { "│   " }
        
        if ($item.PSIsContainer) {
            $script:processedCountAfter++
            
            if ($collapseNoiseDirs -and ($noiseDirPatterns -contains $item.Name)) {
                $inner        = Get-ChildItem -Path $item.FullName -Recurse -ErrorAction SilentlyContinue
                $innerFiles   = ($inner | Where-Object { -not $_.PSIsContainer }).Count
                $innerFolders = ($inner | Where-Object { $_.PSIsContainer }).Count
                
                $script:treeLinesAfter.Add("- $Prefix$connector🚫 $($item.Name)/  ($innerFolders folders, $innerFiles files — collapsed)")
            } else {
                Write-Host "  Verified Folder #$($script:processedCountAfter): $($item.Name)" -ForegroundColor DarkGray
                $script:treeLinesAfter.Add("+ $Prefix$connector📁 $($item.Name)/")
                Build-TreeAfter -Path $item.FullName -Prefix "$Prefix$childPfx"
            }
        } else {
            $icon = Get-FileIcon -ext $item.Extension
            $script:treeLinesAfter.Add("  $Prefix$connector$icon $($item.Name)")
        }
    }
}

Build-TreeAfter -Path $rootResolved

# ── 11. Generate Comprehensive Report ──────────────────────
Write-Host ""
Write-Host "📄 PHASE 6: REPORT GENERATION" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────"

$reportLines = [System.Collections.Generic.List[string]]::new()
$endTime = Get-Date
$duration = $endTime - $startTime

# Header
$reportLines.Add("# 📂 Directory Translation & Renaming Report")
$reportLines.Add("")
$reportLines.Add("> Auto-generated file — do not edit manually.")
$reportLines.Add("> This report documents the complete translation and renaming process.")
$reportLines.Add("")

# Metadata
$reportLines.Add("## 🗂️ Metadata")
$reportLines.Add("")
$reportLines.Add("| Field | Value |")
$reportLines.Add("|-------|-------|")
$reportLines.Add("| **Scan date** | ``$scanDate`` |")
$reportLines.Add("| **Root directory** | ``$rootResolved`` |")
$reportLines.Add("| **WhatIf mode** | ``$WhatIf`` |")
$reportLines.Add("| **FilesOnly mode** | ``$FilesOnly`` |")
$reportLines.Add("| **Translation service** | ``$TranslationService`` |")
$reportLines.Add("| **Total folders (entire scan)** | $totalFolders |")
$reportLines.Add("| **Total files (entire scan)** | $totalFiles |")
$reportLines.Add("| **Items with Chinese characters** | $($script:itemsWithChinese) |")
$reportLines.Add("| **Items renamed** | $($script:renameLog.Count) |")
$reportLines.Add("| **Successful renames** | $($script:renameLog | Where-Object { $_.Status -eq 'Success' } | Measure-Object | Select-Object -ExpandProperty Count) |")
$reportLines.Add("| **Failed renames** | $($script:renameLog | Where-Object { $_.Status -eq 'Failed' } | Measure-Object | Select-Object -ExpandProperty Count) |")
$reportLines.Add("| **Execution time** | $($duration.TotalSeconds.ToString('F2')) seconds |")
$reportLines.Add("")

# Translation Cache
$reportLines.Add("## 🔤 Translation Cache")
$reportLines.Add("")
$reportLines.Add("| Chinese | English |")
$reportLines.Add("|---------|---------|")
foreach ($entry in $script:translationCache.GetEnumerator()) {
    $reportLines.Add("| ``$($entry.Key)`` | ``$($entry.Value)`` |")
}
$reportLines.Add("")

# Rename Audit Log
$reportLines.Add("## 📋 Rename Operations Audit Log")
$reportLines.Add("")
$reportLines.Add("| Original Name | Translation | Item Type | Status | Message | Timestamp |")
$reportLines.Add("|---|---|---|---|---|---|")
foreach ($log in $script:renameLog) {
    $reportLines.Add("| ``$($log.OriginalName)`` | ``$($log.Translation)`` | $($log.ItemType) | **$($log.Status)** | $($log.Message) | $($log.Timestamp) |")
}
$reportLines.Add("")

# Directory Structure BEFORE
$reportLines.Add("## 🌳 Directory Structure — BEFORE Renaming")
$reportLines.Add("")
$reportLines.Add("``````diff")
$reportLines.Add("@@ $rootResolved (BEFORE) @@")
foreach ($line in $script:treeLinesBefore) { $reportLines.Add($line) }
$reportLines.Add("``````")
$reportLines.Add("")

# Directory Structure AFTER
$reportLines.Add("## 🌳 Directory Structure — AFTER Renaming")
$reportLines.Add("")
$reportLines.Add("``````diff")
$reportLines.Add("@@ $rootResolved (AFTER) @@")
foreach ($line in $script:treeLinesAfter) { $reportLines.Add($line) }
$reportLines.Add("``````")
$reportLines.Add("")

# Conventions
$reportLines.Add("## 📖 Reading Conventions")
$reportLines.Add("")
$reportLines.Add("The tree is rendered inside a ``diff`` code block for color distinction.")
$reportLines.Add("")
$reportLines.Add("| Symbol | Meaning |")
$reportLines.Add("|--------|---------|")
$reportLines.Add("| ``+ `` prefix | Expanded folder (green) |")
$reportLines.Add("| ``- `` prefix | Collapsed dependency/build folder (red) |")
$reportLines.Add("| ``  `` (spaces) prefix | File (neutral) |")
$reportLines.Add("| ``🔤`` | Item contained Chinese characters |")
$reportLines.Add("| ``├──`` / ``└──`` | Tree connectors |")
$reportLines.Add("")

# Summary
$reportLines.Add("## 📊 Summary")
$reportLines.Add("")
$reportLines.Add("- **Total items processed:** $($script:processedCount)")
$reportLines.Add("- **Chinese characters detected:** $($script:itemsWithChinese)")
$reportLines.Add("- **Translation operations:** $($script:translationCache.Count)")
$reportLines.Add("- **Rename operations:** $($script:renameLog.Count)")
$reportLines.Add("")

# Count folders and files renamed
$foldersRenamed = ($script:renameLog | Where-Object { $_.ItemType -eq 'Folder' } | Measure-Object | Select-Object -ExpandProperty Count)
$filesRenamed = ($script:renameLog | Where-Object { $_.ItemType -eq 'File' } | Measure-Object | Select-Object -ExpandProperty Count)
$reportLines.Add("- **Folders renamed:** $foldersRenamed")
$reportLines.Add("- **Files renamed:** $filesRenamed")

if ($WhatIf) {
    $reportLines.Add("> ⚠️  **This report was generated in WHATIF mode.** No actual filesystem changes were made.")
    $reportLines.Add("")
}

$reportLines.Add("---")
$reportLines.Add("")
$reportLines.Add("*Generated by ``Generate-Arborescence-Translator-V3.ps1`` on $scanDate*")

# Write report file
$reportPath = Join-Path $outputDirResolved $outputReportFile
[System.IO.File]::WriteAllLines($reportPath, $reportLines, $encoding)

# Write audit CSV
$auditPath = Join-Path $outputDirResolved $outputAuditFile
$script:renameLog | Export-Csv -Path $auditPath -Encoding UTF8 -NoTypeInformation

Write-Host "✅ Report written to: $reportPath" -ForegroundColor Green
Write-Host "✅ Audit log written to: $auditPath" -ForegroundColor Green

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  Process Complete                                          ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
