param(
    [switch]$Worker,
    [string]$Destination,
    [string]$Locale = "enUS",
    [string]$Region = "NA",
    [switch]$NoCinematics,
    [string]$LogFile
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-FolderSizeGB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0.0 }
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if (-not $sum) { return 0.0 }
        [math]::Round(($sum / 1GB), 2)
    } catch { 0.0 }
}

function Write-Log {
    param([string]$Text)
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Text
    $line | Out-File -LiteralPath $LogFile -Append -Encoding utf8
}

function Run-Logged {
    param([string]$Exe,[string[]]$Args,[string]$Title)
    Write-Log $Title
    Write-Log ("Executando: {0} {1}" -f $Exe, ($Args -join " "))
    & $Exe @Args 2>&1 | ForEach-Object {
        $_ | Out-File -LiteralPath $LogFile -Append -Encoding utf8
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$Title falhou (codigo $LASTEXITCODE)."
    }
}

function Find-CMake {
    $cmd = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        "C:\Program Files\CMake\bin\cmake.exe",
        "C:\Program Files (x86)\CMake\bin\cmake.exe"
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Has-VCTools {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $false }
    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    return -not [string]::IsNullOrWhiteSpace(($path | Out-String).Trim())
}

function Ensure-Winget {
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $wg) {
        throw "winget nao encontrado. Atualize o App Installer da Microsoft e tente novamente."
    }
    $wg.Source
}

function Install-Package {
    param([string]$Winget,[string]$Id,[string]$Override = "")
    $args = @("install","--id",$Id,"-e","--accept-package-agreements","--accept-source-agreements")
    if ($Override) { $args += @("--override",$Override) } else { $args += "--silent" }

    Write-Log "Instalando dependencia: $Id"
    & $Winget @args 2>&1 | ForEach-Object {
        $_ | Out-File -LiteralPath $LogFile -Append -Encoding utf8
    }
}

function Download-File {
    param([string]$Url,[string]$OutFile,[string]$Description)
    Write-Log $Description
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    if (-not (Test-Path $OutFile)) { throw "Falha ao baixar: $Description" }
}

function Find-WowRebuild {
    param([string[]]$Roots)
    foreach ($root in $Roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $hit = Get-ChildItem -LiteralPath $root -Filter "wowrebuild.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Ensure-WowRebuildInstalled {
    param(
        [string]$CMake,
        [string]$SourceRoot,
        [string]$BuildRoot,
        [string]$InstallRoot,
        [string]$VcpkgRoot
    )

    # 1) Reutiliza instalacao existente.
    $existing = Find-WowRebuild @($InstallRoot)
    if ($existing) {
        Write-Log "WoWClientRebuilder existente encontrado: $($existing.FullName)"
        return $existing
    }

    $toolchain = Join-Path $VcpkgRoot "scripts\buildsystems\vcpkg.cmake"
    if (-not (Test-Path $toolchain)) { throw "Toolchain do vcpkg nao encontrado: $toolchain" }

    # 2) Configuracao limpa para evitar cache com toolchain errado.
    if (Test-Path $BuildRoot) {
        Write-Log "Limpando build antigo para evitar CMakeCache incorreto..."
        Remove-Item $BuildRoot -Recurse -Force
    }
    if (Test-Path $InstallRoot) {
        Remove-Item $InstallRoot -Recurse -Force
    }
    New-Item $BuildRoot -ItemType Directory -Force | Out-Null
    New-Item $InstallRoot -ItemType Directory -Force | Out-Null

    $env:VCPKG_ROOT = $VcpkgRoot

    Run-Logged -Exe $CMake -Args @(
        "-S",$SourceRoot,
        "-B",$BuildRoot,
        "-G","Visual Studio 17 2022",
        "-A","x64",
        "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
        "-DCMAKE_INSTALL_PREFIX:PATH=$InstallRoot"
    ) -Title "Configurando WoWClientRebuilder"

    Run-Logged -Exe $CMake -Args @(
        "--build",$BuildRoot,
        "--config","Release",
        "--target","wowrebuild",
        "--parallel"
    ) -Title "Compilando wowrebuild.exe"

    # O README oficial indica cmake --install. Aqui forçamos --prefix
    # para impedir que o exe seja instalado em outro local.
    Run-Logged -Exe $CMake -Args @(
        "--install",$BuildRoot,
        "--config","Release",
        "--prefix",$InstallRoot
    ) -Title "Instalando WoWClientRebuilder"

    $installed = Find-WowRebuild @($InstallRoot)
    if ($installed) {
        Write-Log "wowrebuild.exe instalado corretamente: $($installed.FullName)"
        return $installed
    }

    # 3) Recuperacao: se a compilacao gerou o exe mas o install nao o copiou,
    # cria uma pasta portatil com exe + DLLs de runtime do vcpkg.
    $built = Find-WowRebuild @($BuildRoot)
    if (-not $built) {
        throw "A compilacao terminou sem produzir wowrebuild.exe. Veja o log acima."
    }

    Write-Log "O exe foi encontrado no build: $($built.FullName)"
    Write-Log "Recuperando a instalacao portatil..."

    New-Item $InstallRoot -ItemType Directory -Force | Out-Null
    Copy-Item $built.FullName (Join-Path $InstallRoot "wowrebuild.exe") -Force

    # DLLs que estiverem ao lado do exe.
    Get-ChildItem $built.Directory.FullName -Filter "*.dll" -File -ErrorAction SilentlyContinue |
        ForEach-Object { Copy-Item $_.FullName $InstallRoot -Force }

    # DLLs runtime do vcpkg (curl/zlib e dependencias).
    $vcpkgBin = Join-Path $VcpkgRoot "installed\x64-windows\bin"
    if (Test-Path $vcpkgBin) {
        Get-ChildItem $vcpkgBin -Filter "*.dll" -File -ErrorAction SilentlyContinue |
            ForEach-Object { Copy-Item $_.FullName $InstallRoot -Force }
    }

    $recovered = Find-WowRebuild @($InstallRoot)
    if (-not $recovered) { throw "Nao foi possivel montar a instalacao portatil do wowrebuild.exe." }

    Write-Log "Recuperacao concluida: $($recovered.FullName)"
    return $recovered
}

if ($Worker) {
    if ([string]::IsNullOrWhiteSpace($Destination)) { throw "Destino nao informado." }
    if ([string]::IsNullOrWhiteSpace($LogFile)) { $LogFile = Join-Path $env:TEMP "Pariz-Cata434-client.log" }

    New-Item -ItemType Directory -Path (Split-Path $LogFile -Parent) -Force | Out-Null
    "" | Out-File -LiteralPath $LogFile -Encoding utf8

    try {
        Write-Log "PARIZ CATACLYSM 4.3.4 - INSTALADOR V2"
        Write-Log "Destino: $Destination"
        Write-Log "Locale: $Locale | Regiao: $Region"

        $driveRoot = [System.IO.Path]::GetPathRoot($Destination)
        if ([string]::IsNullOrWhiteSpace($driveRoot)) { throw "Destino invalido." }

        $drive = New-Object System.IO.DriveInfo($driveRoot)
        $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB,1)
        Write-Log "Espaco livre: $freeGB GB"
        if ($freeGB -lt 20) { throw "Recomenda-se pelo menos 20 GB livres." }

        New-Item $Destination -ItemType Directory -Force | Out-Null

        $winget = Ensure-Winget

        $cmake = Find-CMake
        if (-not $cmake) {
            Install-Package -Winget $winget -Id "Kitware.CMake"
            Start-Sleep -Seconds 3
            $cmake = Find-CMake
        }
        if (-not $cmake) { throw "CMake nao foi localizado." }
        Write-Log "CMake OK: $cmake"

        if (-not (Has-VCTools)) {
            Install-Package -Winget $winget -Id "Microsoft.VisualStudio.2022.BuildTools" `
                -Override "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
            Start-Sleep -Seconds 5
        }
        if (-not (Has-VCTools)) {
            throw "Visual Studio 2022 Build Tools C++ nao foi localizado. Se acabou de instalar, reinicie o PC e execute novamente."
        }
        Write-Log "Visual Studio Build Tools C++ OK"

        $toolsDrive = [System.IO.Path]::GetPathRoot($Destination)
        $toolsRoot = Join-Path $toolsDrive "ParizCataclysmTools"
        $srcRoot = Join-Path $toolsRoot "WoWClientRebuilder"
        $buildRoot = Join-Path $toolsRoot "WoWClientRebuilder_build"
        $installRoot = Join-Path $toolsRoot "WoWClientRebuilder_install"
        $vcpkgRoot = Join-Path $toolsRoot "vcpkg"
        $tempRoot = Join-Path $toolsRoot "_downloads"

        New-Item $toolsRoot -ItemType Directory -Force | Out-Null
        New-Item $tempRoot -ItemType Directory -Force | Out-Null

        $vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"
        if (-not (Test-Path $vcpkgExe)) {
            Write-Log "Preparando vcpkg..."
            $vcpkgZip = Join-Path $tempRoot "vcpkg.zip"
            $vcpkgExtract = Join-Path $tempRoot "vcpkg-extract"
            if (Test-Path $vcpkgExtract) { Remove-Item $vcpkgExtract -Recurse -Force }
            if (Test-Path $vcpkgRoot) { Remove-Item $vcpkgRoot -Recurse -Force }

            Download-File "https://github.com/microsoft/vcpkg/archive/refs/heads/master.zip" $vcpkgZip "Baixando vcpkg..."
            Expand-Archive $vcpkgZip $vcpkgExtract -Force
            $expanded = Get-ChildItem $vcpkgExtract -Directory | Select-Object -First 1
            Move-Item $expanded.FullName $vcpkgRoot

            Run-Logged -Exe (Join-Path $vcpkgRoot "bootstrap-vcpkg.bat") -Args @("-disableMetrics") -Title "Preparando vcpkg"
        }
        Write-Log "vcpkg OK"

        # Baixa o source apenas se estiver ausente. Assim uma tentativa que falhou nao baixa tudo de novo.
        if (-not (Test-Path (Join-Path $srcRoot "CMakeLists.txt"))) {
            Write-Log "Baixando WoWClientRebuilder..."
            $srcZip = Join-Path $tempRoot "WoWClientRebuilder-main.zip"
            $srcExtract = Join-Path $tempRoot "wcr-extract"
            if (Test-Path $srcExtract) { Remove-Item $srcExtract -Recurse -Force }
            if (Test-Path $srcRoot) { Remove-Item $srcRoot -Recurse -Force }

            Download-File "https://github.com/mangostools/WoWClientRebuilder/archive/refs/heads/main.zip" $srcZip "Baixando WoWClientRebuilder..."
            Expand-Archive $srcZip $srcExtract -Force
            $expandedSrc = Get-ChildItem $srcExtract -Directory | Select-Object -First 1
            Move-Item $expandedSrc.FullName $srcRoot
        }
        Write-Log "Source WoWClientRebuilder OK"

        $wowRebuild = Ensure-WowRebuildInstalled `
            -CMake $cmake `
            -SourceRoot $srcRoot `
            -BuildRoot $buildRoot `
            -InstallRoot $installRoot `
            -VcpkgRoot $vcpkgRoot

        Write-Log "INICIANDO DOWNLOAD/RECONSTRUCAO DO CLIENTE..."
        Write-Log "O proprio WoWClientRebuilder exibira o progresso real no log."

        $args = @(
            "client","4.3.4",
            "--locale",$Locale,
            "--region",$Region,
            "--realmlist","127.0.0.1",
            "--yes"
        )
        if ($NoCinematics) { $args += "--no-cinematics" }
        $args += $Destination

        Run-Logged -Exe $wowRebuild.FullName -Args $args -Title "WoWClientRebuilder - Cataclysm 4.3.4"

        $finalGB = Get-FolderSizeGB $Destination
        Write-Log "CLIENTE CONCLUIDO"
        Write-Log "Tamanho atual da pasta: $finalGB GB"
        Write-Log "Use Wow.exe/Wow-64.exe. Nao execute Launcher.exe."
        exit 0
    }
    catch {
        Write-Log ("ERRO: " + $_.Exception.Message)
        exit 1
    }
}

# ================== INTERFACE ==================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Pariz Cataclysm 4.3.4 - Instalador do Cliente V2"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(850,650)
$form.Font = New-Object System.Drawing.Font("Segoe UI",9)
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "Pariz Cataclysm 4.3.4 - Cliente build 15595"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold",16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(22,18)
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Versao V2: corrige a instalacao do wowrebuild.exe e reaproveita arquivos ja baixados."
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(25,58)
$form.Controls.Add($sub)

$destLabel = New-Object System.Windows.Forms.Label
$destLabel.Text = "Pasta do cliente:"
$destLabel.AutoSize = $true
$destLabel.Location = New-Object System.Drawing.Point(25,100)
$form.Controls.Add($destLabel)

$destBox = New-Object System.Windows.Forms.TextBox
$defaultDrive = if (Test-Path "D:\") { "D:\" } else { "C:\" }
$destBox.Text = Join-Path $defaultDrive "WoW-Cataclysm-434"
$destBox.Size = New-Object System.Drawing.Size(630,25)
$destBox.Location = New-Object System.Drawing.Point(25,125)
$form.Controls.Add($destBox)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = "Escolher..."
$browse.Size = New-Object System.Drawing.Size(110,28)
$browse.Location = New-Object System.Drawing.Point(675,123)
$form.Controls.Add($browse)

$localeBox = New-Object System.Windows.Forms.ComboBox
$localeBox.DropDownStyle = "DropDown"
[void]$localeBox.Items.Add("enUS")
[void]$localeBox.Items.Add("ptBR")
[void]$localeBox.Items.Add("esMX")
$localeBox.Text = "enUS"
$localeBox.Size = New-Object System.Drawing.Size(120,25)
$localeBox.Location = New-Object System.Drawing.Point(25,190)
$form.Controls.Add($localeBox)

$regionBox = New-Object System.Windows.Forms.ComboBox
$regionBox.DropDownStyle = "DropDownList"
[void]$regionBox.Items.Add("NA")
[void]$regionBox.Items.Add("EU")
$regionBox.SelectedIndex = 0
$regionBox.Size = New-Object System.Drawing.Size(90,25)
$regionBox.Location = New-Object System.Drawing.Point(170,190)
$form.Controls.Add($regionBox)

$cinema = New-Object System.Windows.Forms.CheckBox
$cinema.Text = "Sem cinematics (download menor)"
$cinema.AutoSize = $true
$cinema.Location = New-Object System.Drawing.Point(290,192)
$form.Controls.Add($cinema)

$start = New-Object System.Windows.Forms.Button
$start.Text = "INICIAR / CONTINUAR"
$start.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$start.Size = New-Object System.Drawing.Size(200,40)
$start.Location = New-Object System.Drawing.Point(25,240)
$form.Controls.Add($start)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Pronto. Se uma tentativa anterior falhou, pode clicar novamente; a V2 reaproveita o que ja existe."
$status.AutoSize = $false
$status.Size = New-Object System.Drawing.Size(560,45)
$status.Location = New-Object System.Drawing.Point(240,243)
$form.Controls.Add($status)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = "Marquee"
$progress.MarqueeAnimationSpeed = 0
$progress.Size = New-Object System.Drawing.Size(760,22)
$progress.Location = New-Object System.Drawing.Point(25,305)
$form.Controls.Add($progress)

$metrics = New-Object System.Windows.Forms.Label
$metrics.Text = "Cliente gravado: 0 GB | O progresso real aparece no log."
$metrics.AutoSize = $true
$metrics.Location = New-Object System.Drawing.Point(25,340)
$form.Controls.Add($metrics)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = "Vertical"
$logBox.WordWrap = $false
$logBox.Size = New-Object System.Drawing.Size(760,205)
$logBox.Location = New-Object System.Drawing.Point(25,375)
$form.Controls.Add($logBox)

$browse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $destBox.Text = Join-Path $dlg.SelectedPath "WoW-Cataclysm-434"
    }
})

$script:proc = $null
$script:logPath = Join-Path $env:TEMP ("Pariz-Cata434-V2-" + [guid]::NewGuid().ToString("N") + ".log")

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    if (Test-Path $script:logPath) {
        try {
            $lines = Get-Content $script:logPath -Tail 120 -ErrorAction SilentlyContinue
            $logBox.Lines = $lines
            $logBox.SelectionStart = $logBox.TextLength
            $logBox.ScrollToCaret()
        } catch {}
    }

    $gb = Get-FolderSizeGB $destBox.Text
    $metrics.Text = "Cliente gravado: $gb GB | O progresso/velocidade real aparece no log do WoWClientRebuilder."

    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop()
        $start.Enabled = $true
        $browse.Enabled = $true
        $destBox.Enabled = $true
        $localeBox.Enabled = $true
        $regionBox.Enabled = $true
        $cinema.Enabled = $true
        $progress.MarqueeAnimationSpeed = 0

        if ($script:proc.ExitCode -eq 0) {
            $status.Text = "Concluido com sucesso."
            [System.Windows.Forms.MessageBox]::Show("Cliente 4.3.4 concluido em:`r`n$($destBox.Text)","Concluido","OK","Information") | Out-Null
        } else {
            $status.Text = "Parou com erro. Leia a ultima linha do log."
            [System.Windows.Forms.MessageBox]::Show("O processo parou. A V2 manteve os arquivos ja baixados; veja a ultima linha do log.","Erro","OK","Error") | Out-Null
        }
        $script:proc = $null
    }
})

$start.Add_Click({
    $dest = $destBox.Text.Trim()
    if (-not $dest) { return }

    $loc = $localeBox.Text.Trim()
    if (-not $loc) { $loc = "enUS" }
    $reg = $regionBox.Text

    $args = @(
        "-NoProfile","-ExecutionPolicy","Bypass",
        "-File","`"$PSCommandPath`"",
        "-Worker",
        "-Destination","`"$dest`"",
        "-Locale","`"$loc`"",
        "-Region","`"$reg`"",
        "-LogFile","`"$script:logPath`""
    )
    if ($cinema.Checked) { $args += "-NoCinematics" }

    try {
        $start.Enabled = $false
        $browse.Enabled = $false
        $destBox.Enabled = $false
        $localeBox.Enabled = $false
        $regionBox.Enabled = $false
        $cinema.Enabled = $false
        $progress.MarqueeAnimationSpeed = 30
        $status.Text = "Trabalhando... acompanhe o log. Na primeira vez pode instalar CMake/Build Tools."

        $script:proc = Start-Process powershell.exe -ArgumentList $args -Verb RunAs -PassThru -WindowStyle Hidden
        $timer.Start()
    } catch {
        $start.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,"Erro","OK","Error") | Out-Null
    }
})

[void]$form.ShowDialog()
