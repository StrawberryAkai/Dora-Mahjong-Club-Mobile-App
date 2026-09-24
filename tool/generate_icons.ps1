# Regenerates the geometric Dora tile mark with Windows System.Drawing.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
function Write-DoraIcon([string]$RelativePath, [int]$Size) {
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#234D3C'))
    $graphics.ScaleTransform($Size / 100.0, $Size / 100.0)
    $cream = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#F6F5F0'))
    $lime = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#DCEA9C'))
    $green = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#234D3C'))
    $red = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#B95746'))
    $graphics.FillRectangle($lime, 31, 25, 44, 59)
    $graphics.FillRectangle($cream, 25, 19, 44, 59)
    $graphics.FillEllipse($green, 34, 28, 9, 9)
    $graphics.FillEllipse($green, 52, 60, 9, 9)
    $graphics.FillEllipse($red, 41, 42, 14, 14)
    $graphics.FillEllipse($cream, 45, 46, 6, 6)
    $target = Join-Path $projectRoot $RelativePath
    $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
    $cream.Dispose(); $lime.Dispose(); $green.Dispose(); $red.Dispose()
}
$iconSpec = Get-Content -LiteralPath (Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json') -Raw | ConvertFrom-Json
foreach ($icon in $iconSpec.images) {
    $pixelSize = [int]([double]($icon.size -split 'x')[0] * [double]($icon.scale -replace 'x', ''))
    Write-DoraIcon "ios/Runner/Assets.xcassets/AppIcon.appiconset/$($icon.filename)" $pixelSize
}
foreach ($density in @(@('mdpi',48),@('hdpi',72),@('xhdpi',96),@('xxhdpi',144),@('xxxhdpi',192))) {
    Write-DoraIcon "android/app/src/main/res/mipmap-$($density[0])/ic_launcher.png" $density[1]
}
Write-DoraIcon 'web/favicon.png' 32
foreach ($size in @(192,512)) {
    Write-DoraIcon "web/icons/Icon-$size.png" $size
    Write-DoraIcon "web/icons/Icon-maskable-$size.png" $size
}
Write-Output 'Dora platform icons generated.'
