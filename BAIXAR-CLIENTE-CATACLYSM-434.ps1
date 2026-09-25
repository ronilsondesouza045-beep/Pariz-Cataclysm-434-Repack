param(
    [switch]$Worker,
    [string]$Destination,
    [string]$Locale = "ptBR",
    [string]$Region = "NA",
    [switch]$NoCinematics,
    [string]$LogFile
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log {
    param([string]$Text)
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Text
    $line | Out-File -LiteralPath $LogFile -Append -Encoding utf8
}

function Get-FolderSizeGB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0.0 }
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
        if (-not $sum) { return 0.0 }
        return [math]::Round($sum / 1GB, 2)
    } catch { return 0.0 }
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

    $install = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null

    return -not [string]::IsNullOrWhiteSpace(($install | Out-String).Trim())
}

function Ensure-Winget {
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $wg) {
        throw "winget nao foi encontrado. Atualize o App Installer da Microsoft e tente novamente."
    }
    return $wg.Source
}

function Install-Package {
    param(
        [string]$Winget,
        [string]$Id,
        [string]$Override = ""
    )

    Write-Log "Instalando dependencia: $Id"

    $arguments = @(
        "install","--id",$Id,"-e",
        "--accept-package-agreements",
        "--accept-source-agreements"
    )

    if ($Override) {
        $arguments += @("--override",$Override)
    } else {
        $arguments += "--silent"
    }

    & $Winget @arguments 2>&1 | ForEach-Object {
        $_ | Out-File -LiteralPath $LogFile -Append -Encoding utf8
    }
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )

    Write-Log $Description
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing

    if (-not (Test-Path $OutFile)) {
        throw "Falha ao baixar: $Description"
    }
}

function Run-ProcessLogged {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$Title
    )

    Write-Log $Title
    Write-Log ("Executando: {0} {1}" -f $Executable, ($Arguments -join " "))

    & $Executable @Arguments 2>&1 | ForEach-Object {
        $_ | Out-File -LiteralPath $LogFile -Append -Encoding utf8
    }

    $code = $LASTEXITCODE
    Write-Log "Codigo de saida: $code"

    if ($code -ne 0) {
        throw "$Title falhou (codigo $code)."
    }
}

function Find-WowRebuild {
    param([string[]]$Roots)

    foreach ($root in $Roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }

        $hit = Get-ChildItem -LiteralPath $root `
            -Filter "wowrebuild.exe" `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($hit) { return $hit }
    }

    return $null
}

if ($Worker) {
    if ([string]::IsNullOrWhiteSpace($Destination)) {
        throw "Destino nao informado."
    }

    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        $LogFile = Join-Path $env:TEMP "Pariz-Cata434-V3.log"
    }

    New-Item -ItemType Directory -Path (Split-Path $LogFile -Parent) -Force | Out-Null
    "" | Out-File -LiteralPath $LogFile -Encoding utf8

    try {
        Write-Log "PARIZ CATACLYSM 4.3.4 - INSTALADOR V3"
        Write-Log "Destino: $Destination"
        Write-Log "Locale: $Locale | Regiao: $Region"

        # Nao misturar com um cliente que o usuario ja possui.
        if ((Test-Path (Join-Path $Destination "Wow.exe")) -or
            (Test-Path (Join-Path $Destination "Wow-64.exe"))) {
            throw "A pasta escolhida ja contem um cliente WoW. Escolha uma pasta nova/vazia para evitar alterar seu cliente existente."
        }

        $driveRoot = [System.IO.Path]::GetPathRoot($Destination)
        if ([string]::IsNullOrWhiteSpace($driveRoot)) {
            throw "Destino invalido: $Destination"
        }

        $drive = New-Object System.IO.DriveInfo($driveRoot)
        $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
        Write-Log "Espaco livre: $freeGB GB"

        if ($freeGB -lt 20) {
            throw "Espaco livre insuficiente. Recomenda-se pelo menos 20 GB livres."
        }

        New-Item $Destination -ItemType Directory -Force | Out-Null

        $winget = Ensure-Winget

        $cmake = Find-CMake
        if (-not $cmake) {
            Install-Package -Winget $winget -Id "Kitware.CMake"
            Start-Sleep -Seconds 3
            $cmake = Find-CMake
        }

        if (-not $cmake) {
            throw "CMake nao foi localizado."
        }

        Write-Log "CMake OK: $cmake"

        if (-not (Has-VCTools)) {
            Install-Package `
                -Winget $winget `
                -Id "Microsoft.VisualStudio.2022.BuildTools" `
                -Override "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

            Start-Sleep -Seconds 5
        }

        if (-not (Has-VCTools)) {
            throw "Visual Studio 2022 Build Tools C++ nao foi localizado. Se acabou de instalar, reinicie o Windows e execute novamente."
        }

        Write-Log "Visual Studio 2022 Build Tools C++ OK"

        $toolsDrive = [System.IO.Path]::GetPathRoot($Destination)
        $toolsRoot = Join-Path $toolsDrive "ParizCataclysmTools"
        $srcRoot = Join-Path $toolsRoot "WoWClientRebuilder"
        $buildRoot = Join-Path $toolsRoot "WoWClientRebuilder_build"
        $installRoot = Join-Path $toolsRoot "WoWClientRebuilder_install"
        $vcpkgRoot = Join-Path $toolsRoot "vcpkg"
        $tempRoot = Join-Path $toolsRoot "_downloads"

        New-Item $toolsRoot -ItemType Directory -Force | Out-Null
        New-Item $tempRoot -ItemType Directory -Force | Out-Null

        # vcpkg
        $vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"

        if (-not (Test-Path $vcpkgExe)) {
            Write-Log "Preparando vcpkg..."

            $vcpkgZip = Join-Path $tempRoot "vcpkg.zip"
            $vcpkgExtract = Join-Path $tempRoot "vcpkg-extract"

            if (Test-Path $vcpkgExtract) {
                Remove-Item $vcpkgExtract -Recurse -Force
            }

            if (Test-Path $vcpkgRoot) {
                Remove-Item $vcpkgRoot -Recurse -Force
            }

            Download-File `
                -Url "https://github.com/microsoft/vcpkg/archive/refs/heads/master.zip" `
                -OutFile $vcpkgZip `
                -Description "Baixando vcpkg oficial..."

            Expand-Archive -LiteralPath $vcpkgZip -DestinationPath $vcpkgExtract -Force

            $expanded = Get-ChildItem $vcpkgExtract -Directory | Select-Object -First 1
            if (-not $expanded) {
                throw "Nao consegui extrair vcpkg."
            }

            Move-Item $expanded.FullName $vcpkgRoot

            $bootstrap = Join-Path $vcpkgRoot "bootstrap-vcpkg.bat"

            Run-ProcessLogged `
                -Executable $bootstrap `
                -Arguments @("-disableMetrics") `
                -Title "Preparando vcpkg"
        }

        Write-Log "vcpkg OK"

        # Source do WoWClientRebuilder
        $cmakeLists = Join-Path $srcRoot "CMakeLists.txt"

        if (-not (Test-Path $cmakeLists)) {
            Write-Log "Baixando WoWClientRebuilder..."

            $srcZip = Join-Path $tempRoot "WoWClientRebuilder-main.zip"
            $srcExtract = Join-Path $tempRoot "wcr-extract"

            if (Test-Path $srcExtract) {
                Remove-Item $srcExtract -Recurse -Force
            }

            if (Test-Path $srcRoot) {
                Remove-Item $srcRoot -Recurse -Force
            }

            Download-File `
                -Url "https://github.com/mangostools/WoWClientRebuilder/archive/refs/heads/main.zip" `
                -OutFile $srcZip `
                -Description "Baixando WoWClientRebuilder..."

            Expand-Archive -LiteralPath $srcZip -DestinationPath $srcExtract -Force

            $expandedSrc = Get-ChildItem $srcExtract -Directory | Select-Object -First 1
            if (-not $expandedSrc) {
                throw "Nao consegui extrair WoWClientRebuilder."
            }

            Move-Item $expandedSrc.FullName $srcRoot
        }

        Write-Log "Source WoWClientRebuilder OK"

        $toolchain = Join-Path $vcpkgRoot "scripts\buildsystems\vcpkg.cmake"

        if (-not (Test-Path $toolchain)) {
            throw "Toolchain do vcpkg nao encontrado: $toolchain"
        }

        $env:VCPKG_ROOT = $vcpkgRoot

        # Tenta primeiro o script oficial do proprio projeto.
        $officialBuildScript = Join-Path $srcRoot "scripts\build-install.ps1"

        $wowRebuild = Find-WowRebuild @($installRoot)

        if (-not $wowRebuild) {
            # Limpa somente build/install temporarios da ferramenta.
            if (Test-Path $buildRoot) {
                Write-Log "Removendo build temporario antigo para evitar CMakeCache incorreto..."
                Remove-Item $buildRoot -Recurse -Force
            }

            if (Test-Path $installRoot) {
                Remove-Item $installRoot -Recurse -Force
            }

            if (Test-Path $officialBuildScript) {
                Write-Log "Usando o build-install.ps1 OFICIAL do WoWClientRebuilder..."

                Run-ProcessLogged `
                    -Executable "powershell.exe" `
                    -Arguments @(
                        "-NoProfile",
                        "-ExecutionPolicy","Bypass",
                        "-File",$officialBuildScript,
                        "-VcpkgToolchain",$toolchain
                    ) `
                    -Title "Compilando/instalando WoWClientRebuilder pelo script oficial"
            }
            else {
                Write-Log "Script oficial nao encontrado; usando configuracao manual documentada."

                Run-ProcessLogged `
                    -Executable $cmake `
                    -Arguments @(
                        "-S",$srcRoot,
                        "-B",$buildRoot,
                        "-G","Visual Studio 17 2022",
                        "-A","x64",
                        "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
                        "-DCMAKE_INSTALL_PREFIX=$installRoot"
                    ) `
                    -Title "Configurando WoWClientRebuilder"

                Run-ProcessLogged `
                    -Executable $cmake `
                    -Arguments @(
                        "--build",$buildRoot,
                        "--config","Release"
                    ) `
                    -Title "Compilando WoWClientRebuilder"

                Run-ProcessLogged `
                    -Executable $cmake `
                    -Arguments @(
                        "--install",$buildRoot,
                        "--config","Release"
                    ) `
                    -Title "Instalando WoWClientRebuilder"
            }

            $wowRebuild = Find-WowRebuild @(
                $installRoot,
                $buildRoot,
                $toolsRoot
            )
        }

        if (-not $wowRebuild) {
            throw "A ferramenta compilou/instalou, mas wowrebuild.exe ainda nao foi localizado. Copie as ultimas linhas do log."
        }

        Write-Log "wowrebuild.exe encontrado: $($wowRebuild.FullName)"
        Write-Log "Iniciando reconstrucao do Cataclysm 4.3.4 build 15595..."

        $rebuildArguments = @(
            "client","4.3.4",
            "--locale",$Locale,
            "--region",$Region,
            "--realmlist","127.0.0.1",
            "--yes"
        )

        if ($NoCinematics) {
            $rebuildArguments += "--no-cinematics"
        }

        $rebuildArguments += $Destination

        Run-ProcessLogged `
            -Executable $wowRebuild.FullName `
            -Arguments $rebuildArguments `
            -Title "Baixando/reconstruindo Cataclysm 4.3.4"

        $finalGB = Get-FolderSizeGB $Destination
        Write-Log "CLIENTE CONCLUIDO"
        Write-Log "Tamanho atual: $finalGB GB"
        Write-Log "Use Wow.exe ou Wow-64.exe. Nao execute Launcher.exe."

        exit 0
    }
    catch {
        Write-Log ("ERRO: " + $_.Exception.Message)
        exit 1
    }
}

# =========================
# INTERFACE
# =========================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Pariz Cataclysm 4.3.4 - Instalador do Cliente V3"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(860,660)
$form.Font = New-Object System.Drawing.Font("Segoe UI",9)
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "Pariz Cataclysm 4.3.4 - Cliente build 15595"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold",16)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(22,18)
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "V3 usa o script oficial de compilação/instalação do WoWClientRebuilder."
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(25,58)
$form.Controls.Add($sub)

$destLabel = New-Object System.Windows.Forms.Label
$destLabel.Text = "Pasta NOVA onde o cliente será criado:"
$destLabel.AutoSize = $true
$destLabel.Location = New-Object System.Drawing.Point(25,100)
$form.Controls.Add($destLabel)

$destBox = New-Object System.Windows.Forms.TextBox
$defaultDrive = if (Test-Path "D:\") { "D:\" } else { "C:\" }
$baseDest = Join-Path $defaultDrive "WoW-Cataclysm-434"
if ((Test-Path (Join-Path $baseDest "Wow.exe")) -or (Test-Path (Join-Path $baseDest "Wow-64.exe"))) {
    $baseDest = Join-Path $defaultDrive "WoW-Cataclysm-434-NOVO"
}
$destBox.Text = $baseDest
$destBox.Size = New-Object System.Drawing.Size(640,25)
$destBox.Location = New-Object System.Drawing.Point(25,125)
$form.Controls.Add($destBox)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = "Escolher..."
$browse.Size = New-Object System.Drawing.Size(110,28)
$browse.Location = New-Object System.Drawing.Point(685,123)
$form.Controls.Add($browse)

$localeBox = New-Object System.Windows.Forms.ComboBox
$localeBox.DropDownStyle = "DropDown"
[void]$localeBox.Items.Add("ptBR")
[void]$localeBox.Items.Add("enUS")
[void]$localeBox.Items.Add("esMX")
$localeBox.Text = "ptBR"
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
$cinema.Text = "Sem cinematics"
$cinema.AutoSize = $true
$cinema.Location = New-Object System.Drawing.Point(290,192)
$form.Controls.Add($cinema)

$start = New-Object System.Windows.Forms.Button
$start.Text = "INICIAR"
$start.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$start.Size = New-Object System.Drawing.Size(190,40)
$start.Location = New-Object System.Drawing.Point(25,240)
$form.Controls.Add($start)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Escolha uma pasta nova/vazia. Seu WoW existente não será usado nem alterado."
$status.AutoSize = $false
$status.Size = New-Object System.Drawing.Size(570,45)
$status.Location = New-Object System.Drawing.Point(230,243)
$form.Controls.Add($status)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = "Marquee"
$progress.MarqueeAnimationSpeed = 0
$progress.Size = New-Object System.Drawing.Size(770,22)
$progress.Location = New-Object System.Drawing.Point(25,305)
$form.Controls.Add($progress)

$metrics = New-Object System.Windows.Forms.Label
$metrics.Text = "Gravado no cliente novo: 0 GB"
$metrics.AutoSize = $true
$metrics.Location = New-Object System.Drawing.Point(25,340)
$form.Controls.Add($metrics)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = "Vertical"
$logBox.WordWrap = $false
$logBox.Size = New-Object System.Drawing.Size(770,215)
$logBox.Location = New-Object System.Drawing.Point(25,375)
$form.Controls.Add($logBox)

$browse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Escolha uma pasta-base. O instalador criara uma subpasta nova."
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $candidate = Join-Path $dlg.SelectedPath "WoW-Cataclysm-434"
        if ((Test-Path (Join-Path $candidate "Wow.exe")) -or (Test-Path (Join-Path $candidate "Wow-64.exe"))) {
            $candidate = Join-Path $dlg.SelectedPath "WoW-Cataclysm-434-NOVO"
        }
        $destBox.Text = $candidate
    }
})

$script:proc = $null
$script:logPath = Join-Path $env:TEMP ("Pariz-Cata434-V3-" + [guid]::NewGuid().ToString("N") + ".log")

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
    $metrics.Text = "Gravado no cliente novo: $gb GB"

    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop()
        $progress.MarqueeAnimationSpeed = 0
        $start.Enabled = $true
        $browse.Enabled = $true
        $destBox.Enabled = $true
        $localeBox.Enabled = $true
        $regionBox.Enabled = $true
        $cinema.Enabled = $true

        if ($script:proc.ExitCode -eq 0) {
            $status.Text = "Concluído com sucesso."
            [System.Windows.Forms.MessageBox]::Show(
                "Cliente 4.3.4 concluído em:`r`n$($destBox.Text)",
                "Concluído","OK","Information"
            ) | Out-Null
        } else {
            $status.Text = "Parou com erro. Veja a última linha do log."
            [System.Windows.Forms.MessageBox]::Show(
                "O processo parou. Leia as últimas linhas do log mostradas na janela.",
                "Erro","OK","Error"
            ) | Out-Null
        }

        $script:proc = $null
    }
})

$start.Add_Click({
    $dest = $destBox.Text.Trim()
    if (-not $dest) { return }

    if ((Test-Path (Join-Path $dest "Wow.exe")) -or (Test-Path (Join-Path $dest "Wow-64.exe"))) {
        [System.Windows.Forms.MessageBox]::Show(
            "Essa pasta já contém WoW. Escolha uma pasta nova/vazia para não alterar seu cliente existente.",
            "Escolha outra pasta","OK","Warning"
        ) | Out-Null
        return
    }

    $loc = $localeBox.Text.Trim()
    if (-not $loc) { $loc = "ptBR" }

    $reg = $regionBox.Text

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy","Bypass",
        "-File","`"$PSCommandPath`"",
        "-Worker",
        "-Destination","`"$dest`"",
        "-Locale","`"$loc`"",
        "-Region","`"$reg`"",
        "-LogFile","`"$script:logPath`""
    )

    if ($cinema.Checked) {
        $arguments += "-NoCinematics"
    }

    try {
        $start.Enabled = $false
        $browse.Enabled = $false
        $destBox.Enabled = $false
        $localeBox.Enabled = $false
        $regionBox.Enabled = $false
        $cinema.Enabled = $false
        $progress.MarqueeAnimationSpeed = 30
        $status.Text = "Preparando a ferramenta oficial... acompanhe o log."

        $script:proc = Start-Process powershell.exe `
            -ArgumentList $arguments `
            -Verb RunAs `
            -PassThru `
            -WindowStyle Hidden

        $timer.Start()
    }
    catch {
        $start.Enabled = $true
        $progress.MarqueeAnimationSpeed = 0
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Erro","OK","Error"
        ) | Out-Null
    }
})

[void]$form.ShowDialog()
