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
        return [math]::Round(($sum / 1GB), 2)
    } catch { return 0.0 }
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
        throw "$Title falhou (codigo $LASTEXITCODE). Veja o log."
    }
}

function Find-CMake {
    $cmd = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("C:\Program Files\CMake\bin\cmake.exe","C:\Program Files (x86)\CMake\bin\cmake.exe")) {
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
        throw "winget nao foi encontrado. Atualize o App Installer pela Microsoft Store e execute novamente."
    }
    return $wg.Source
}

function Install-Package {
    param([string]$Winget,[string]$Id,[string]$ExtraOverride = "")
    $args = @("install","--id",$Id,"-e","--accept-package-agreements","--accept-source-agreements")
    if ($ExtraOverride) { $args += @("--override",$ExtraOverride) } else { $args += "--silent" }

    Write-Log "Instalando dependencia: $Id"
    & $Winget @args 2>&1 | ForEach-Object {
        $_ | Out-File -LiteralPath $LogFile -Append -Encoding utf8
    }
}

function Download-File {
    param([string]$Url,[string]$OutFile,[string]$Description)
    Write-Log $Description
    Write-Log "Fonte: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    if (-not (Test-Path $OutFile)) { throw "Falha ao baixar $Description." }
}

if ($Worker) {
    if ([string]::IsNullOrWhiteSpace($Destination)) { throw "Destino nao informado." }
    if ([string]::IsNullOrWhiteSpace($LogFile)) { $LogFile = Join-Path $env:TEMP "Pariz-Cata434-client.log" }

    New-Item -ItemType Directory -Path (Split-Path $LogFile -Parent) -Force | Out-Null
    "" | Out-File -LiteralPath $LogFile -Encoding utf8

    try {
        Write-Log "PARIZ CATACLYSM 4.3.4 - INSTALADOR DO CLIENTE"
        Write-Log "Destino: $Destination"
        Write-Log "Locale: $Locale"
        Write-Log "Regiao CDN: $Region"
        Write-Log "O WoWClientRebuilder reconstruira o cliente a partir dos servidores publicos de distribuicao da Blizzard."

        $driveRoot = [System.IO.Path]::GetPathRoot($Destination)
        if ([string]::IsNullOrWhiteSpace($driveRoot)) { throw "Destino invalido: $Destination" }

        $drive = New-Object System.IO.DriveInfo($driveRoot)
        $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
        Write-Log "Espaco livre no destino: $freeGB GB"
        if ($freeGB -lt 20) { throw "Espaco livre insuficiente. Recomenda-se pelo menos 20 GB livres." }

        New-Item -ItemType Directory -Path $Destination -Force | Out-Null

        $winget = Ensure-Winget

        $cmake = Find-CMake
        if (-not $cmake) {
            Install-Package -Winget $winget -Id "Kitware.CMake"
            Start-Sleep -Seconds 3
            $cmake = Find-CMake
        }
        if (-not $cmake) { throw "CMake nao foi localizado mesmo depois da instalacao." }
        Write-Log "CMake: $cmake"

        if (-not (Has-VCTools)) {
            Install-Package -Winget $winget -Id "Microsoft.VisualStudio.2022.BuildTools" `
                -ExtraOverride "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
            Start-Sleep -Seconds 5
        }
        if (-not (Has-VCTools)) {
            throw "Visual Studio 2022 Build Tools com C++ nao foi localizado. Se acabou de instalar, reinicie o Windows e execute novamente."
        }
        Write-Log "Visual Studio 2022 Build Tools C++: OK"

        $toolsDrive = [System.IO.Path]::GetPathRoot($Destination)
        $toolsRoot = Join-Path $toolsDrive "ParizCataclysmTools"
        $srcRoot = Join-Path $toolsRoot "WoWClientRebuilder"
        $buildRoot = Join-Path $toolsRoot "WoWClientRebuilder_build"
        $installRoot = Join-Path $toolsRoot "WoWClientRebuilder_install"
        $vcpkgRoot = Join-Path $toolsRoot "vcpkg"
        $tempRoot = Join-Path $toolsRoot "_downloads"

        New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        $vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"
        if (-not (Test-Path $vcpkgExe)) {
            Write-Log "Preparando vcpkg..."
            $vcpkgZip = Join-Path $tempRoot "vcpkg.zip"
            $vcpkgExtract = Join-Path $tempRoot "vcpkg-extract"
            if (Test-Path $vcpkgExtract) { Remove-Item $vcpkgExtract -Recurse -Force }
            if (Test-Path $vcpkgRoot) { Remove-Item $vcpkgRoot -Recurse -Force }

            Download-File -Url "https://github.com/microsoft/vcpkg/archive/refs/heads/master.zip" `
                -OutFile $vcpkgZip -Description "Baixando vcpkg do GitHub oficial da Microsoft..."

            Expand-Archive -LiteralPath $vcpkgZip -DestinationPath $vcpkgExtract -Force
            $expanded = Get-ChildItem $vcpkgExtract -Directory | Select-Object -First 1
            Move-Item $expanded.FullName $vcpkgRoot

            $bootstrap = Join-Path $vcpkgRoot "bootstrap-vcpkg.bat"
            Run-Logged -Exe $bootstrap -Args @("-disableMetrics") -Title "Compilando vcpkg"
        }
        Write-Log "vcpkg: OK"

        Write-Log "Preparando WoWClientRebuilder..."
        $srcZip = Join-Path $tempRoot "WoWClientRebuilder-main.zip"
        $srcExtract = Join-Path $tempRoot "wcr-extract"

        if (Test-Path $srcExtract) { Remove-Item $srcExtract -Recurse -Force }
        if (Test-Path $srcRoot) { Remove-Item $srcRoot -Recurse -Force }
        if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force }
        if (Test-Path $installRoot) { Remove-Item $installRoot -Recurse -Force }

        Download-File -Url "https://github.com/mangostools/WoWClientRebuilder/archive/refs/heads/main.zip" `
            -OutFile $srcZip -Description "Baixando o codigo do WoWClientRebuilder..."

        Expand-Archive -LiteralPath $srcZip -DestinationPath $srcExtract -Force
        $expandedSrc = Get-ChildItem $srcExtract -Directory | Select-Object -First 1
        Move-Item $expandedSrc.FullName $srcRoot

        $toolchain = Join-Path $vcpkgRoot "scripts\buildsystems\vcpkg.cmake"

        Run-Logged -Exe $cmake -Args @(
            "-S",$srcRoot,
            "-B",$buildRoot,
            "-G","Visual Studio 17 2022",
            "-A","x64",
            "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
            "-DCMAKE_INSTALL_PREFIX=$installRoot"
        ) -Title "Configurando WoWClientRebuilder"

        Run-Logged -Exe $cmake -Args @("--build",$buildRoot,"--config","Release","--parallel") `
            -Title "Compilando WoWClientRebuilder"

        Run-Logged -Exe $cmake -Args @("--install",$buildRoot,"--config","Release") `
            -Title "Instalando WoWClientRebuilder"

        $wowRebuild = Get-ChildItem $installRoot -Filter "wowrebuild.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $wowRebuild) { throw "wowrebuild.exe nao foi encontrado depois da compilacao." }

        Write-Log "WoWClientRebuilder pronto: $($wowRebuild.FullName)"
        Write-Log "Iniciando Cataclysm 4.3.4 build 15595..."
        Write-Log "Um cliente com um idioma costuma ficar perto de 15 GB; o valor exato pode variar."

        $rebuildArgs = @(
            "client","4.3.4",
            "--locale",$Locale,
            "--region",$Region,
            "--realmlist","127.0.0.1",
            "--yes"
        )
        if ($NoCinematics) { $rebuildArgs += "--no-cinematics" }
        $rebuildArgs += $Destination

        Run-Logged -Exe $wowRebuild.FullName -Args $rebuildArgs -Title "Baixando e reconstruindo o cliente"

        $finalGB = Get-FolderSizeGB -Path $Destination
        Write-Log "CLIENTE CONCLUIDO"
        Write-Log "Tamanho atual da pasta: $finalGB GB"
        Write-Log "Destino: $Destination"
        Write-Log "Use Wow.exe/Wow-64.exe. Nao execute Launcher.exe."
        exit 0
    }
    catch {
        Write-Log ("ERRO: " + $_.Exception.Message)
        exit 1
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Pariz Cataclysm 4.3.4 - Baixar Cliente"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(820,620)
$form.MinimumSize = New-Object System.Drawing.Size(820,620)
$form.Font = New-Object System.Drawing.Font("Segoe UI",9)
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "Pariz Cataclysm 4.3.4 - Cliente build 15595"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold",16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(22,18)
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Prepara o WoWClientRebuilder e reconstrói o cliente usando os servidores públicos de distribuição da Blizzard."
$sub.AutoSize = $false
$sub.Size = New-Object System.Drawing.Size(750,38)
$sub.Location = New-Object System.Drawing.Point(25,55)
$form.Controls.Add($sub)

$destLabel = New-Object System.Windows.Forms.Label
$destLabel.Text = "Pasta onde o cliente será criado:"
$destLabel.AutoSize = $true
$destLabel.Location = New-Object System.Drawing.Point(25,105)
$form.Controls.Add($destLabel)

$destBox = New-Object System.Windows.Forms.TextBox
$defaultDrive = if (Test-Path "D:\") { "D:\" } else { "C:\" }
$destBox.Text = Join-Path $defaultDrive "WoW-Cataclysm-434"
$destBox.Size = New-Object System.Drawing.Size(610,25)
$destBox.Location = New-Object System.Drawing.Point(25,130)
$form.Controls.Add($destBox)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = "Escolher..."
$browse.Size = New-Object System.Drawing.Size(110,28)
$browse.Location = New-Object System.Drawing.Point(650,128)
$form.Controls.Add($browse)

$localeLabel = New-Object System.Windows.Forms.Label
$localeLabel.Text = "Idioma/locale:"
$localeLabel.AutoSize = $true
$localeLabel.Location = New-Object System.Drawing.Point(25,175)
$form.Controls.Add($localeLabel)

$localeBox = New-Object System.Windows.Forms.ComboBox
$localeBox.DropDownStyle = "DropDown"
[void]$localeBox.Items.Add("enUS")
[void]$localeBox.Items.Add("ptBR")
[void]$localeBox.Items.Add("esMX")
$localeBox.Text = "enUS"
$localeBox.Size = New-Object System.Drawing.Size(120,25)
$localeBox.Location = New-Object System.Drawing.Point(25,198)
$form.Controls.Add($localeBox)

$regionLabel = New-Object System.Windows.Forms.Label
$regionLabel.Text = "Região CDN:"
$regionLabel.AutoSize = $true
$regionLabel.Location = New-Object System.Drawing.Point(175,175)
$form.Controls.Add($regionLabel)

$regionBox = New-Object System.Windows.Forms.ComboBox
$regionBox.DropDownStyle = "DropDownList"
[void]$regionBox.Items.Add("NA")
[void]$regionBox.Items.Add("EU")
$regionBox.SelectedIndex = 0
$regionBox.Size = New-Object System.Drawing.Size(90,25)
$regionBox.Location = New-Object System.Drawing.Point(175,198)
$form.Controls.Add($regionBox)

$cinema = New-Object System.Windows.Forms.CheckBox
$cinema.Text = "Baixar sem cinematics (menor download)"
$cinema.AutoSize = $true
$cinema.Location = New-Object System.Drawing.Point(300,200)
$form.Controls.Add($cinema)

$sizeInfo = New-Object System.Windows.Forms.Label
$sizeInfo.Text = "Estimativa: cerca de 15 GB para um idioma. Recomenda-se pelo menos 20 GB livres."
$sizeInfo.AutoSize = $true
$sizeInfo.Location = New-Object System.Drawing.Point(25,240)
$form.Controls.Add($sizeInfo)

$start = New-Object System.Windows.Forms.Button
$start.Text = "INICIAR DOWNLOAD"
$start.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$start.Size = New-Object System.Drawing.Size(190,38)
$start.Location = New-Object System.Drawing.Point(25,272)
$form.Controls.Add($start)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Pronto."
$status.AutoSize = $false
$status.Size = New-Object System.Drawing.Size(540,38)
$status.Location = New-Object System.Drawing.Point(230,278)
$form.Controls.Add($status)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.Size = New-Object System.Drawing.Size(735,22)
$progress.Location = New-Object System.Drawing.Point(25,325)
$form.Controls.Add($progress)

$metrics = New-Object System.Windows.Forms.Label
$metrics.Text = "Gravado no destino: 0 GB"
$metrics.AutoSize = $true
$metrics.Location = New-Object System.Drawing.Point(25,355)
$form.Controls.Add($metrics)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = "Vertical"
$logBox.WordWrap = $false
$logBox.Size = New-Object System.Drawing.Size(735,155)
$logBox.Location = New-Object System.Drawing.Point(25,385)
$form.Controls.Add($logBox)

$browse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Escolha a pasta onde o cliente Cataclysm será criado"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $destBox.Text = Join-Path $dlg.SelectedPath "WoW-Cataclysm-434"
    }
})

$script:workerProcess = $null
$script:logPath = Join-Path $env:TEMP ("Pariz-Cata434-" + [guid]::NewGuid().ToString("N") + ".log")
$script:lastSizeCheck = [datetime]::MinValue

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000

$timer.Add_Tick({
    if (Test-Path $script:logPath) {
        try {
            $lines = Get-Content -LiteralPath $script:logPath -Tail 80 -ErrorAction SilentlyContinue
            $logBox.Lines = $lines
            $logBox.SelectionStart = $logBox.TextLength
            $logBox.ScrollToCaret()
        } catch {}
    }

    if ((Get-Date) - $script:lastSizeCheck -gt [timespan]::FromSeconds(8)) {
        $script:lastSizeCheck = Get-Date
        $gb = Get-FolderSizeGB -Path $destBox.Text
        $remaining = [math]::Max(0,[math]::Round((15 - $gb),1))
        $metrics.Text = "Gravado: $gb GB | Restante aproximado (base 15 GB): $remaining GB"
        $pct = [math]::Min(99,[math]::Max(0,[int](($gb / 15.0) * 100)))
        if ($script:workerProcess -and -not $script:workerProcess.HasExited) { $progress.Value = $pct }
    }

    if ($script:workerProcess -and $script:workerProcess.HasExited) {
        $timer.Stop()
        $start.Enabled = $true
        $browse.Enabled = $true
        $destBox.Enabled = $true
        $localeBox.Enabled = $true
        $regionBox.Enabled = $true
        $cinema.Enabled = $true

        if ($script:workerProcess.ExitCode -eq 0) {
            $progress.Value = 100
            $status.Text = "Concluído. Cliente criado em: " + $destBox.Text
            [System.Windows.Forms.MessageBox]::Show(
                "Cliente Cataclysm 4.3.4 concluído.`r`n`r`nPasta:`r`n$($destBox.Text)`r`n`r`nUse Wow.exe ou Wow-64.exe. Não execute Launcher.exe.",
                "Pariz Cataclysm - Concluído","OK","Information"
            ) | Out-Null
        } else {
            $status.Text = "O processo parou com erro. Veja o log abaixo."
            [System.Windows.Forms.MessageBox]::Show(
                "O instalador parou com erro. Veja as últimas linhas do log na janela.",
                "Pariz Cataclysm - Erro","OK","Error"
            ) | Out-Null
        }
        $script:workerProcess = $null
    }
})

$start.Add_Click({
    $dest = $destBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($dest)) {
        [System.Windows.Forms.MessageBox]::Show("Escolha uma pasta de destino.") | Out-Null
        return
    }

    $loc = $localeBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($loc)) { $loc = "enUS" }
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
        $status.Text = "Preparando dependências e download. O Windows pode pedir permissão de administrador..."
        $progress.Value = 0

        $script:workerProcess = Start-Process powershell.exe -ArgumentList $args -Verb RunAs -PassThru -WindowStyle Hidden
        $timer.Start()
    }
    catch {
        $start.Enabled = $true
        $browse.Enabled = $true
        $destBox.Enabled = $true
        $localeBox.Enabled = $true
        $regionBox.Enabled = $true
        $cinema.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,"Erro","OK","Error") | Out-Null
    }
})

[void]$form.ShowDialog()
