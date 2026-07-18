# go-to-istanbul — Windows PowerShell Installer
# Usage: iex (iwr -UseBasicParsing https://raw.githubusercontent.com/ravizikrillah/go-to-istanbul/main/install.ps1).Content

$ErrorActionPreference = "Stop"

# ─── Colors helper ────────────────────────────────────────────────────────────
function Write-Header ($text) {
    Write-Host "`n=== $text ===" -ForegroundColor Cyan
}

function Write-Success ($text) {
    Write-Host "✅ $text" -ForegroundColor Green
}

function Write-WarningMsg ($text) {
    Write-Host "⚠️  $text" -ForegroundColor Yellow
}

function Write-ErrorMsg ($text) {
    Write-Host "❌ $text" -ForegroundColor Red
}

Write-Host @"
  ┌────────────────────────────────────────┐
  │        go-to-istanbul installer        │
  │  Go coverage -> Istanbul HTML Report    │
  └────────────────────────────────────────┘
"@

# ─── Prerequisite Checks ──────────────────────────────────────────────────────
if (!(Get-Command node -ErrorAction SilentlyContinue)) {
    Write-ErrorMsg "Node.js not found. Please install Node.js (v18+) from https://nodejs.org"
    exit 1
}

$nodeVer = (node -v).Trim().TrimStart('v').Split('.')[0]
if ([int]$nodeVer -lt 18) {
    Write-ErrorMsg "Node.js v18+ is required. Current version: $(node -v)"
    exit 1
}

if (!(Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-ErrorMsg "npm not found. Please ensure Node.js installation is complete."
    exit 1
}

Write-Success "Node.js $(node -v) detected."

# ─── Parse Arguments ──────────────────────────────────────────────────────────
$globalInstall = $false
$uninstall = $false

foreach ($arg in $args) {
    if ($arg -eq "--global" -or $arg -eq "-g") {
        $globalInstall = $true
    }
    if ($arg -eq "--uninstall") {
        $uninstall = $true
    }
}

$deps = "istanbul-lib-coverage", "istanbul-lib-report", "istanbul-reports"

# ─── Uninstall Logic ──────────────────────────────────────────────────────────
if ($uninstall) {
    Write-Header "Uninstalling go-to-istanbul"
    
    # Global Cleanup
    $globalDir = Join-Path $env:USERPROFILE ".go-to-istanbul"
    if (Test-Path $globalDir) {
        Write-Host "Removing global library directory: $globalDir"
        Remove-Item -Recurse -Force $globalDir
    }
    
    # Local Cleanup
    if (Test-Path "go-to-istanbul.js") {
        Write-Host "Removing local go-to-istanbul.js"
        Remove-Item -Force "go-to-istanbul.js"
    }
    if (Test-Path "coverage.ps1") {
        Write-Host "Removing local coverage.ps1"
        Remove-Item -Force "coverage.ps1"
    }
    
    # Remove package files if generated locally and belong to go-to-istanbul
    if (Test-Path "package.json") {
        $json = Get-Content "package.json" -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($json -and $json.devDependencies -and $json.devDependencies."istanbul-lib-report") {
            Write-Host "Removing local node_modules"
            if (Test-Path "node_modules") { Remove-Item -Recurse -Force "node_modules" }
            Write-Host "Removing local package.json & package-lock.json"
            Remove-Item -Force "package.json", "package-lock.json" -ErrorAction SilentlyContinue
        }
    }

    # Revert .gitignore additions
    if (Test-Path ".gitignore") {
        Write-Host "Cleaning up .gitignore..."
        $content = Get-Content ".gitignore"
        $newContent = @()
        $skip = $false
        
        foreach ($line in $content) {
            if ($line -match "# go-to-istanbul") {
                $skip = $true
                continue
            }
            if ($skip) {
                if ($line -match "^(node_modules/|coverage\.out|coverage-report/|\.nyc_output/|go-to-istanbul\.js|coverage\.ps1|package\.json|package-lock\.json)$") {
                    continue
                }
                $skip = $false
            }
            $newContent += $line
        }
        Set-Content -Path ".gitignore" -Value $newContent
    }
    
    Write-Success "Uninstall complete!"
    exit 0
}

# ─── Install Logic ────────────────────────────────────────────────────────────
if ($globalInstall) {
    Write-Header "Installing Globally"
    
    $globalDir = Join-Path $env:USERPROFILE ".go-to-istanbul"
    if (!(Test-Path $globalDir)) {
        New-Item -ItemType Directory -Path $globalDir | Out-Null
    }
    
    Write-Host "Installing Istanbul dependencies to $globalDir..."
    Start-Process npm -ArgumentList "install --prefix `"$globalDir`" $([string]::Join(' ', $deps))" -NoNewWindow -Wait
    
    Write-Host "Downloading go-to-istanbul script..."
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ravizikrillah/go-to-istanbul/main/index.js" -OutFile (Join-Path $globalDir "go-to-istanbul.js")
    
    # Create PowerShell wrapper
    $wrapperContent = @"
@echo off
set "NODE_PATH=$globalDir\node_modules"
node "$globalDir\go-to-istanbul.js" %*
"@
    $cmdPath = Join-Path $globalDir "go-to-istanbul.cmd"
    Set-Content -Path $cmdPath -Value $wrapperContent
    
    Write-Success "Installed globally!"
    Write-WarningMsg "To run it from anywhere, please add this folder to your PATH environment variable:"
    Write-Host "   $globalDir" -ForegroundColor Yellow
} else {
    Write-Header "Installing Locally"
    
    Write-Host "Installing Istanbul dependencies locally..."
    Start-Process npm -ArgumentList "install --save-dev $([string]::Join(' ', $deps))" -NoNewWindow -Wait
    
    Write-Host "Downloading go-to-istanbul script..."
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ravizikrillah/go-to-istanbul/main/index.js" -OutFile "go-to-istanbul.js"
    
    # Create local convenience PowerShell script
    $ps1Content = @"
# Runs Go tests with coverage and generates Istanbul HTML report
`$input = if (`$args[0]) { `$args[0] } else { "coverage.out" }
`$output = if (`$args[1]) { `$args[1] } else { "coverage-report" }

Write-Host ""
`$frames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
`$idx = 0

# Start go test as a background job
`$job = Start-Job -ScriptBlock {
    param(`$inp)
    go test -coverpkg=./... -coverprofile=`$inp ./...
} -ArgumentList `$input

# Show spinner while test is running
while (`$job.State -eq "Running") {
    `$frame = `$frames[`$idx++ % `$frames.Length]
    Write-Host "`r`x1b[1;36m`$frame`x1b[0m  Running Backend Unit Tests..." -NoNewline
    Start-Sleep -Milliseconds 80
}

# Clear spinner line
Write-Host "`r`x1b[K" -NoNewline

# Fetch job results
`$result = Receive-Job -Job `$job -Keep
`$jobState = `$job.State
Remove-Job `$job

if (`$jobState -ne "Completed" -or !(Test-Path `$input)) {
    Write-Host "❌  go test failed:`n" -ForegroundColor Red
    `$result | Out-String | Write-Host
    exit 1
}

Write-Host "✅  Tests passed`n" -ForegroundColor Green

# Run go-to-istanbul converter
node go-to-istanbul.js -i `$input -o `$output -o
"@
    Set-Content -Path "coverage.ps1" -Value $ps1Content

    
    # Update .gitignore
    $gitignoreEntries = @(
        "node_modules/",
        "coverage.out",
        "coverage-report/",
        ".nyc_output/",
        "go-to-istanbul.js",
        "coverage.ps1",
        "package.json",
        "package-lock.json"
    )

    
    if (Test-Path ".gitignore") {
        Write-Host "Updating .gitignore..."
        $content = Get-Content ".gitignore"
        $newEntries = @()
        foreach ($entry in $gitignoreEntries) {
            if ($content -notcontains $entry) {
                $newEntries += $entry
            }
        }
        if ($newEntries.Count -gt 0) {
            if ($content -notcontains "# go-to-istanbul") {
                Add-Content -Path ".gitignore" -Value "`n# go-to-istanbul"
            }
            foreach ($entry in $newEntries) {
                Add-Content -Path ".gitignore" -Value $entry
            }
            Write-Success ".gitignore updated."
        } else {
            Write-Host ".gitignore is already up-to-date."
        }
    } else {
        Write-Host "Creating .gitignore..."
        Set-Content -Path ".gitignore" -Value "# go-to-istanbul"
        foreach ($entry in $gitignoreEntries) {
            Add-Content -Path ".gitignore" -Value $entry
        }
        Write-Success ".gitignore created."
    }
    
    Write-Success "Installation complete!"
    Write-Host "`nQuick Start:"
    Write-Host "  Run: .\coverage.ps1" -ForegroundColor Yellow
}
