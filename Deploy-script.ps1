[CmdletBinding()]
param(
    [Parameter()]
    [string]$ExpertsPath = "C:\\Users\\marth\\AppData\\Roaming\\MetaQuotes\\Terminal\\E62C655ED163FFC555DD40DBEA67E6BB\\MQL5\\Experts",

    [Parameter()]
    [string]$IncludePath = "C:\\Users\\marth\\AppData\\Roaming\\MetaQuotes\\Terminal\\E62C655ED163FFC555DD40DBEA67E6BB\\MQL5\\Include",

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Say($message, $color = 'White') {
    Write-Host $message -ForegroundColor $color
}

function Require-Folder($path, $label) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "The $label folder '$path' does not exist. Please create it manually and run the script again." 
    }
}

try {
    $repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    Say "Looking in this repo folder        : $repoRoot" 'Cyan'
    Say "Copying EA files into             : $ExpertsPath" 'Cyan'
    Say "Copying include files into        : $IncludePath" 'Cyan'
    if ($DryRun) { Say "Running in preview mode (dry run). No files will be changed." 'Yellow' }

    Require-Folder -path $ExpertsPath -label 'Experts'
    Require-Folder -path $IncludePath -label 'Include'

    $includeSource = Join-Path $repoRoot 'Include'
    if (Test-Path -LiteralPath $includeSource) {
        if ($DryRun) {
            Say "[Dry Run] Would copy new and updated include files from '$includeSource' into '$IncludePath' without removing existing files." 'Yellow'
        } else {
            Say "Copying include files from '$includeSource' into '$IncludePath'. Existing files not present in the repo will be left untouched." 'White'
            $null = & robocopy $includeSource $IncludePath '/E' '/XO' '/COPY:DAT' '/R:1' '/W:1'
            $code = $LASTEXITCODE
            if ($code -gt 7) {
                throw "Robocopy reported an error while copying include files (exit code $code)."
            }
            Say "Include files are up to date." 'Green'
        }
    } else {
        Say "The repo does not contain an 'Include' folder at '$includeSource'. Skipping include files." 'Yellow'
    }

    $expertFiles = @(
        'MainACAlgorithm.mq5',
        'OldStableMainACAlgo.mq5',
        'ACBreakRevertPro.mq5',
        'ACBreakRevertPro_Fast_CustomMax.mq5',
        'BreakRevertPro.mq5',
        'ACMultiSymbolAlgorithm.mq5',
        'DifferentEAs/ACMultiSACBreakRevertPro.mq5',
        'BreakRevertPro.ex5',
        'test.mq5',
        'test.ex5'
    )

    foreach ($file in $expertFiles) {
        $sourceFile = Join-Path $repoRoot $file
        if (-not (Test-Path -LiteralPath $sourceFile)) {
            Say "Skipping '$file' because it was not found in the repo." 'Yellow'
            continue
        }

        $destFile = Join-Path $ExpertsPath (Split-Path $file -Leaf)

        if ($DryRun) {
            if (Test-Path -LiteralPath $destFile) {
                Say "[Dry Run] Would overwrite existing '$destFile' with the repo version of '$file'." 'Yellow'
            } else {
                Say "[Dry Run] Would create new file '$destFile' from '$file'." 'Yellow'
            }
        } else {
            $targetExists = Test-Path -LiteralPath $destFile
            Copy-Item -Path $sourceFile -Destination $destFile -Force
            if ($targetExists) {
                Say "Replaced '$destFile' with the repo version of '$file'." 'Green'
            } else {
                Say "Created new file '$destFile' from '$file'." 'Green'
            }
        }
    }

    Say "All done." 'Green'
}
catch {
    Say "Deployment stopped: $_" 'Red'
    exit 1
}
