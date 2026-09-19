@echo off
setlocal EnableExtensions
title Folder Cover - Drag and Drop V2
set "FC_SELF=%~f0"

rem ==================== PENGATURAN (boleh diubah) ====================
rem Nama file gambar (tanpa ekstensi) yang diprioritaskan sebagai cover.
rem Dipisah koma, urutan = prioritas.
set "FC_NAMES=cover,folder,front,poster"

rem 1 = jika tidak ada gambar dengan nama di atas, pakai gambar pertama (urut nama)
rem 0 = folder tanpa gambar bernama di atas dilewati
set "FC_FALLBACK=1"
rem 1 = gambar tampil UTUH (tidak dicrop), sisa area icon dibiarkan transparan
rem 0 = gambar dicrop persegi dari tengah supaya memenuhi seluruh icon
set "FC_FIT=1"
rem ===================================================================

echo.
echo ==============================================
echo       FOLDER COVER - DRAG AND DROP  V2
echo ==============================================
echo.

if "%~1"=="" goto noargs

echo Pilih tindakan:
echo.
echo   [1] Pasang cover di folder ini saja
echo   [2] Pasang cover di folder ini + semua subfolder
echo   [3] HAPUS cover (kembali ke icon default) di folder ini + semua subfolder
echo   [Q] Batal
echo.
choice /c 123Q /n /m "Pilihan Anda (1/2/3/Q): "
set "CH=%errorlevel%"

set "FC_MODE="
if "%CH%"=="1" set "FC_MODE=SINGLE"
if "%CH%"=="2" set "FC_MODE=TREE"
if "%CH%"=="3" set "FC_MODE=UNDO"
if not defined FC_MODE goto cancelled

set "HAD_ERR=0"

:next
if "%~1"=="" goto done
set "FC_TARGET=%~1"

echo.
echo ----------------------------------------------
echo Folder: "%FC_TARGET%"
echo ----------------------------------------------

if not exist "%FC_TARGET%\." goto notfolder

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText($env:FC_SELF); $m='::PS'+'_BEGIN'; $i=$c.LastIndexOf($m); & ([scriptblock]::Create($c.Substring($i+$m.Length)))"
if errorlevel 1 set "HAD_ERR=1"
goto advance

:notfolder
echo Dilewati: item ini bukan folder.
set "HAD_ERR=1"

:advance
shift
goto next

:noargs
echo Tidak ada folder yang dipilih.
echo.
echo Cara pakai: drag satu atau beberapa folder ke file BAT ini.
echo.
pause
exit /b 1

:cancelled
echo.
echo Dibatalkan.
echo.
pause
exit /b 0

:done
echo.
echo ==============================================
if "%HAD_ERR%"=="0" (
    echo SEMUA PROSES SELESAI
) else (
    echo ADA PROSES YANG GAGAL ATAU DILEWATI. Cek pesan di atas.
)
echo ==============================================
echo.
pause
endlocal
exit /b 0

::PS_BEGIN
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ImageExts  = '.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff'
$CoverNames = @($env:FC_NAMES -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$Fallback   = ($env:FC_FALLBACK -eq '1')
$Fit        = ($env:FC_FIT -ne '0')
$Mode       = $env:FC_MODE
$Target     = $env:FC_TARGET
$IconRel    = '.\.foldericon\cover.ico'

# ---------------------------------------------------------------
# Helper
# ---------------------------------------------------------------
function Unlock-Item {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { $null = & attrib.exe -h -s -r $Path }
}

function Test-Protected {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full.Length -le 2) { return $true }   # root drive, mis. "D:"
    foreach ($bad in @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $bad) { continue }
        $b = $bad.TrimEnd('\')
        if ($full -ieq $b -or $full.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-SubFolders {
    param([string]$Path)
    foreach ($d in @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        # lewati junction/symlink supaya tidak berputar atau keluar dari folder target
        if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $d
        Get-SubFolders -Path $d.FullName
    }
}

function Get-Cover {
    param([IO.DirectoryInfo]$Folder)

    $images = @(
        Get-ChildItem -LiteralPath $Folder.FullName -File -ErrorAction SilentlyContinue |
        Where-Object { $ImageExts -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object Name
    )
    if ($images.Count -eq 0) { return $null }

    foreach ($n in $CoverNames) {
        $hit = $images | Where-Object { $_.BaseName -ieq $n } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    if ($Fallback) { return $images[0] }
    return $null
}

# ---------------------------------------------------------------
# Buat file .ico 256x256 dari gambar (center-crop, koreksi EXIF)
# ---------------------------------------------------------------
function New-CoverIcon {
    param([string]$ImagePath, [string]$IcoPath)

    $srcStream = $null; $img = $null; $bmp = $null; $g = $null
    $pngStream = $null; $icoStream = $null; $bw = $null

    try {
        $bytesIn   = [IO.File]::ReadAllBytes($ImagePath)
        $srcStream = New-Object IO.MemoryStream (, $bytesIn)
        $img       = [System.Drawing.Image]::FromStream($srcStream)

        if ($img.PropertyIdList -contains 0x0112) {
            $o = [int]$img.GetPropertyItem(0x0112).Value[0]
            switch ($o) {
                3 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
                6 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
                8 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
            }
        }

        $bmp = New-Object System.Drawing.Bitmap 256, 256
        $bmp.SetResolution(96, 96)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        $sx = 256.0 / [double]$img.Width
        $sy = 256.0 / [double]$img.Height
        if ($Fit) { $scale = [Math]::Min($sx, $sy) }   # utuh, tanpa crop
        else      { $scale = [Math]::Max($sx, $sy) }   # crop tengah, penuh
        $w = [int][Math]::Round($img.Width * $scale)
        $h = [int][Math]::Round($img.Height * $scale)
        $x = [int][Math]::Round((256 - $w) / 2)
        $y = [int][Math]::Round((256 - $h) / 2)
        $g.DrawImage($img, $x, $y, $w, $h)

        $pngStream = New-Object IO.MemoryStream
        $bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $png = $pngStream.ToArray()

        $icoStream = New-Object IO.MemoryStream
        $bw = New-Object IO.BinaryWriter ($icoStream)
        $bw.Write([UInt16]0)            # reserved
        $bw.Write([UInt16]1)            # type = icon
        $bw.Write([UInt16]1)            # jumlah gambar
        $bw.Write([Byte]0)              # lebar  (0 = 256)
        $bw.Write([Byte]0)              # tinggi (0 = 256)
        $bw.Write([Byte]0)              # palet
        $bw.Write([Byte]0)              # reserved
        $bw.Write([UInt16]1)            # planes
        $bw.Write([UInt16]32)           # bit per pixel
        $bw.Write([UInt32]$png.Length)  # ukuran data
        $bw.Write([UInt32]22)           # offset data
        $bw.Write($png)
        $bw.Flush()

        [IO.File]::WriteAllBytes($IcoPath, $icoStream.ToArray())
    }
    finally {
        if ($bw)        { $bw.Dispose() }
        if ($icoStream) { $icoStream.Dispose() }
        if ($pngStream) { $pngStream.Dispose() }
        if ($g)         { $g.Dispose() }
        if ($bmp)       { $bmp.Dispose() }
        if ($img)       { $img.Dispose() }
        if ($srcStream) { $srcStream.Dispose() }
    }
}

# ---------------------------------------------------------------
# desktop.ini: gabungkan (bukan timpa) supaya setting lain aman
# ---------------------------------------------------------------
function Add-BeforeTrailingBlanks {
    param($List, [string]$Line)
    $pos = $List.Count
    while ($pos -gt 0 -and $List[$pos - 1].Trim() -eq '') { $pos-- }
    $List.Insert($pos, $Line)
}

function Set-DesktopIni {
    param([string]$IniPath, [string]$IconRelative)

    $lines = @()
    if (Test-Path -LiteralPath $IniPath) {
        $lines = @(Get-Content -LiteralPath $IniPath -ErrorAction SilentlyContinue)
    }

    $out      = New-Object 'System.Collections.Generic.List[string]'
    $iconLine = "IconResource=$IconRelative,0"
    $inShell  = $false
    $hasShell = $false
    $inserted = $false

    foreach ($l in $lines) {
        $s = [string]$l
        $t = $s.Trim()
        if ($t -match '^\[.*\]$') {
            if ($inShell -and -not $inserted) { Add-BeforeTrailingBlanks $out $iconLine; $inserted = $true }
            $inShell = ($t -ieq '[.ShellClassInfo]')
            if ($inShell) { $hasShell = $true }
            $out.Add($s)
            continue
        }
        if ($inShell -and $t -match '^(IconResource|IconFile|IconIndex)\s*=') { continue }
        $out.Add($s)
    }

    if ($hasShell -and -not $inserted) { Add-BeforeTrailingBlanks $out $iconLine }
    if (-not $hasShell) {
        $out.Insert(0, $iconLine)
        $out.Insert(0, '[.ShellClassInfo]')
    }

    [IO.File]::WriteAllLines($IniPath, $out.ToArray(), [Text.Encoding]::Unicode)
}

# ---------------------------------------------------------------
# Pasang cover
# ---------------------------------------------------------------
function Set-FolderCover {
    param([IO.DirectoryInfo]$Folder, [IO.FileInfo]$Cover)

    $iconDir  = Join-Path $Folder.FullName '.foldericon'
    $iconPath = Join-Path $iconDir 'cover.ico'
    $ini      = Join-Path $Folder.FullName 'desktop.ini'
    $bak      = Join-Path $Folder.FullName 'desktop.ini.before-folder-cover.bak'

    if (-not (Test-Path -LiteralPath $iconDir)) {
        New-Item -ItemType Directory -Path $iconDir -Force | Out-Null
    }
    New-CoverIcon -ImagePath $Cover.FullName -IcoPath $iconPath

    if (Test-Path -LiteralPath $ini) {
        $raw = Get-Content -LiteralPath $ini -Raw -ErrorAction SilentlyContinue
        $alreadyOurs = ($raw -and ($raw -match '\.foldericon'))
        # backup hanya untuk desktop.ini ASLI milik pengguna, dan hanya sekali
        if (-not $alreadyOurs -and -not (Test-Path -LiteralPath $bak)) {
            Copy-Item -LiteralPath $ini -Destination $bak -Force
        }
        Unlock-Item $ini   # kalau hidden+system, penulisan bisa gagal
    }

    Set-DesktopIni -IniPath $ini -IconRelative $IconRel

    $null = & attrib.exe +h +s $ini
    $null = & attrib.exe +h +s $iconDir
    $null = & attrib.exe +s $Folder.FullName
}

# ---------------------------------------------------------------
# Hapus cover (undo)
# ---------------------------------------------------------------
function Remove-FolderCover {
    param([IO.DirectoryInfo]$Folder)

    $iconDir  = Join-Path $Folder.FullName '.foldericon'
    $iconPath = Join-Path $iconDir 'cover.ico'
    $ini      = Join-Path $Folder.FullName 'desktop.ini'
    $bak      = Join-Path $Folder.FullName 'desktop.ini.before-folder-cover.bak'

    # bukan buatan script ini -> jangan disentuh
    if (-not (Test-Path -LiteralPath $iconPath)) { return $false }

    if (Test-Path -LiteralPath $ini) {
        Unlock-Item $ini
        if (Test-Path -LiteralPath $bak) {
            Unlock-Item $bak
            Copy-Item -LiteralPath $bak -Destination $ini -Force
            Remove-Item -LiteralPath $bak -Force
            $null = & attrib.exe +h +s $ini
        }
        else {
            $kept = @(
                Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue |
                Where-Object { $_ -notmatch '^\s*IconResource\s*=.*\.foldericon' }
            )
            $meaningful = @($kept | Where-Object { $_.Trim() -ne '' -and $_.Trim() -notmatch '^\[.*\]$' })
            if ($meaningful.Count -eq 0) {
                Remove-Item -LiteralPath $ini -Force
            }
            else {
                [IO.File]::WriteAllLines($ini, [string[]]$kept, [Text.Encoding]::Unicode)
                $null = & attrib.exe +h +s $ini
            }
        }
    }

    Unlock-Item $iconDir
    Remove-Item -LiteralPath $iconPath -Force
    if (@(Get-ChildItem -LiteralPath $iconDir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -LiteralPath $iconDir -Force
    }

    # atribut System pada folder hanya dilepas kalau sudah tidak ada desktop.ini
    if (-not (Test-Path -LiteralPath $ini)) { $null = & attrib.exe -s $Folder.FullName }

    return $true
}

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------
try {
    if (-not $Target -or -not (Test-Path -LiteralPath $Target -PathType Container)) {
        throw 'Folder target tidak valid atau tidak ditemukan.'
    }
    if (Test-Protected $Target) {
        throw 'Root drive dan folder sistem (Windows, Program Files) tidak diizinkan demi keamanan.'
    }

    $root    = Get-Item -LiteralPath $Target
    $folders = @($root)
    if ($Mode -ne 'SINGLE') { $folders += @(Get-SubFolders -Path $root.FullName) }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Mode   : $Mode"
Write-Host "Folder : $($folders.Count)"
Write-Host ""

$ok = 0; $skip = 0; $fail = 0

foreach ($folder in $folders) {
    try {
        if ($Mode -eq 'UNDO') {
            if (Remove-FolderCover -Folder $folder) {
                Write-Host "[HAPUS]   $($folder.FullName)" -ForegroundColor Green
                $ok++
            }
            else { $skip++ }
            continue
        }

        $cover = Get-Cover -Folder $folder
        if (-not $cover) { $skip++; continue }

        Write-Host "[PROSES]  $($folder.FullName)" -ForegroundColor Green
        Write-Host "          Cover: $($cover.Name)"
        Set-FolderCover -Folder $folder -Cover $cover
        $ok++
    }
    catch {
        $fail++
        Write-Host "          GAGAL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# minta Explorer menyegarkan icon
try {
    Add-Type -Namespace FolderCover -Name Native -MemberDefinition '[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);'
    [FolderCover.Native]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}
catch { }

Write-Host ""
Write-Host "Berhasil : $ok"  -ForegroundColor Cyan
Write-Host "Dilewati : $skip (tanpa gambar / bukan buatan script ini)" -ForegroundColor Cyan
Write-Host "Gagal    : $fail" -ForegroundColor Cyan
Write-Host ""
Write-Host "Foto asli tidak dihapus, dipindahkan, atau diganti nama." -ForegroundColor Green
Write-Host "Jika icon belum berubah, tutup lalu buka lagi File Explorer."

if ($fail -gt 0) { exit 2 }
exit 0
