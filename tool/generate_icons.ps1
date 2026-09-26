# Regenerates platform icons by resizing the club logo with Windows System.Drawing.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets/images/club_logo.png'
$backgroundColor = [System.Drawing.ColorTranslator]::FromHtml('#F6F5F0')
$legacyArtScale = 0.9
$minimumVisibleAlpha = 16

function Get-VisibleBounds([System.Drawing.Bitmap]$Bitmap) {
    $bounds = [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    $lock = $null
    $minX = $Bitmap.Width
    $minY = $Bitmap.Height
    $maxX = -1
    $maxY = -1
    $rowLength = $Bitmap.Width * 4
    $row = [byte[]]::new($rowLength)

    try {
        $lock = $Bitmap.LockBits(
            $bounds,
            [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )

        for ($y = 0; $y -lt $Bitmap.Height; $y++) {
            $rowAddress = [System.IntPtr]::Add($lock.Scan0, [int]($y * $lock.Stride))
            [System.Runtime.InteropServices.Marshal]::Copy($rowAddress, $row, 0, $rowLength)
            for ($x = 0; $x -lt $Bitmap.Width; $x++) {
                # Ignore near-invisible export noise when measuring the logo's visible bounds.
                if ($row[($x * 4) + 3] -ge $minimumVisibleAlpha) {
                    if ($x -lt $minX) { $minX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }
    }
    finally {
        if ($null -ne $lock) {
            $Bitmap.UnlockBits($lock)
        }
    }

    if ($maxX -lt $minX -or $maxY -lt $minY) {
        throw 'The source logo does not contain any visible pixels.'
    }

    return [System.Drawing.Rectangle]::new($minX, $minY, ($maxX - $minX + 1), ($maxY - $minY + 1))
}

function Get-MaximumVisibleRadius([System.Drawing.Bitmap]$Bitmap, [System.Drawing.Rectangle]$Crop) {
    $bounds = [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    $lock = $null
    $rowLength = $Bitmap.Width * 4
    $row = [byte[]]::new($rowLength)
    $centerX = $Crop.Left + ($Crop.Width / 2.0)
    $centerY = $Crop.Top + ($Crop.Height / 2.0)
    $maxDistanceSquared = 0.0

    try {
        $lock = $Bitmap.LockBits(
            $bounds,
            [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )

        for ($y = $Crop.Top; $y -lt ($Crop.Top + $Crop.Height); $y++) {
            $rowAddress = [System.IntPtr]::Add($lock.Scan0, [int]($y * $lock.Stride))
            [System.Runtime.InteropServices.Marshal]::Copy($rowAddress, $row, 0, $rowLength)
            for ($x = $Crop.Left; $x -lt ($Crop.Left + $Crop.Width); $x++) {
                if ($row[($x * 4) + 3] -ge $minimumVisibleAlpha) {
                    $dx = ($x + 0.5) - $centerX
                    $dy = ($y + 0.5) - $centerY
                    $distanceSquared = ($dx * $dx) + ($dy * $dy)
                    if ($distanceSquared -gt $maxDistanceSquared) {
                        $maxDistanceSquared = $distanceSquared
                    }
                }
            }
        }
    }
    finally {
        if ($null -ne $lock) {
            $Bitmap.UnlockBits($lock)
        }
    }

    if ($maxDistanceSquared -le 0) {
        throw 'The source logo does not have a measurable visible radius.'
    }

    return [Math]::Sqrt($maxDistanceSquared)
}

function Write-Icon(
    [System.Drawing.Bitmap]$Source,
    [System.Drawing.Rectangle]$Crop,
    [double]$VisibleRadius,
    [string]$RelativePath,
    [int]$Size,
    [string]$Fit,
    [bool]$TransparentBackground = $false
) {
    $bitmap = $null
    $graphics = $null
    try {
        $bitmap = [System.Drawing.Bitmap]::new(
            $Size,
            $Size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        if ($TransparentBackground) {
            $graphics.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        }
        else {
            $graphics.Clear($backgroundColor)
        }

        if ($Fit -eq 'legacy') {
            $scale = [Math]::Min(
                ($Size * $legacyArtScale) / $Crop.Width,
                ($Size * $legacyArtScale) / $Crop.Height
            )
        }
        elseif ($Fit -like 'radius:*') {
            $targetRadius = [double]($Fit.Substring(7)) * $Size
            $scale = $targetRadius / $VisibleRadius
        }
        else {
            throw "Unsupported icon fit mode: $Fit"
        }

        $drawWidth = $Crop.Width * $scale
        $drawHeight = $Crop.Height * $scale
        $destination = [System.Drawing.RectangleF]::new(
            [single](($Size - $drawWidth) / 2.0),
            [single](($Size - $drawHeight) / 2.0),
            [single]$drawWidth,
            [single]$drawHeight
        )
        $graphics.DrawImage(
            $Source,
            $destination,
            $Crop,
            [System.Drawing.GraphicsUnit]::Pixel
        )

        $target = Join-Path $projectRoot $RelativePath
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $bitmap) { $bitmap.Dispose() }
    }
}

function Write-Utf8File([string]$RelativePath, [string]$Content) {
    $target = Join-Path $projectRoot $RelativePath
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
    [System.IO.File]::WriteAllText($target, $Content, [System.Text.UTF8Encoding]::new($false))
}

$source = $null
try {
    $source = [System.Drawing.Bitmap]::new($sourcePath)
    $visibleBounds = Get-VisibleBounds $source
    $visibleRadius = Get-MaximumVisibleRadius $source $visibleBounds

    # Use the existing Xcode catalog so generated filenames stay aligned with iOS build settings.
    $iosCatalogPath = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'
    $iosCatalog = Get-Content -LiteralPath $iosCatalogPath -Raw | ConvertFrom-Json
    foreach ($icon in $iosCatalog.images) {
        $pixelSize = [int]([double]($icon.size -split 'x')[0] * [double]($icon.scale -replace 'x', ''))
        Write-Icon $source $visibleBounds $visibleRadius "ios/Runner/Assets.xcassets/AppIcon.appiconset/$($icon.filename)" $pixelSize 'legacy'
    }

    # Keep the original launcher bitmap for Android versions before adaptive icons.
    foreach ($density in @(@('mdpi', 48), @('hdpi', 72), @('xhdpi', 96), @('xxhdpi', 144), @('xxxhdpi', 192))) {
        Write-Icon $source $visibleBounds $visibleRadius "android/app/src/main/res/mipmap-$($density[0])/ic_launcher.png" $density[1] 'legacy'
    }

    # Adaptive icon foreground art stays inside Android's circular safe zone.
    foreach ($density in @(@('mdpi', 108), @('hdpi', 162), @('xhdpi', 216), @('xxhdpi', 324), @('xxxhdpi', 432))) {
        Write-Icon $source $visibleBounds $visibleRadius "android/app/src/main/res/drawable-$($density[0])/ic_launcher_foreground.png" $density[1] 'radius:0.2962962962962963' $true
    }

    Write-Utf8File 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml' @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/dora_icon_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
'@
    Write-Utf8File 'android/app/src/main/res/values/dora_icon_background.xml' @'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="dora_icon_background">#F6F5F0</color>
</resources>
'@

    Write-Icon $source $visibleBounds $visibleRadius 'web/favicon.png' 32 'legacy'
    foreach ($size in @(192, 512)) {
        Write-Icon $source $visibleBounds $visibleRadius "web/icons/Icon-$size.png" $size 'legacy'
        Write-Icon $source $visibleBounds $visibleRadius "web/icons/Icon-maskable-$size.png" $size 'radius:0.38'
    }

    Write-Output "Platform icons generated from $sourcePath."
}
finally {
    if ($null -ne $source) { $source.Dispose() }
}
