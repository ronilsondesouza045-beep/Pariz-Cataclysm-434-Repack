# Cliente Cataclysm 4.3.4 — Build 15595

O cliente do World of Warcraft **não está incluído no repack**.

A versão usada com este servidor é:

```text
World of Warcraft: Cataclysm
Versão: 4.3.4
Build: 15595
```

## Opção fácil — instalador PowerShell

Este repositório inclui:

**`BAIXAR-CLIENTE-CATACLYSM-434.ps1`**

Ele abre uma interface do Windows. A pessoa escolhe a pasta e clica em **INICIAR DOWNLOAD**.

O instalador prepara automaticamente o **WoWClientRebuilder**, que reconstrói o cliente usando os endpoints públicos de distribuição da Blizzard.

A interface mostra:

- pasta de destino;
- idioma/locale;
- região CDN;
- log do processo;
- GB já gravados no disco;
- estimativa aproximada do que falta.

> Um cliente 4.3.4 com um idioma costuma ficar perto de **15 GB**. O valor exato pode variar. Recomenda-se ter pelo menos **20 GB livres**.

### Copiar e colar no PowerShell

Abra o PowerShell e cole o bloco inteiro:

```powershell
$Arquivo = "$env:TEMP\BAIXAR-CLIENTE-CATACLYSM-434.ps1"
Invoke-WebRequest "https://raw.githubusercontent.com/ronilsondesouza045-beep/Pariz-Cataclysm-434-Repack/main/BAIXAR-CLIENTE-CATACLYSM-434.ps1" -OutFile $Arquivo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Arquivo
```

O Windows pode pedir permissão de administrador na primeira execução para instalar dependências de compilação.

## WoWClientRebuilder

O link original continua aqui:

**https://github.com/mangostools/WoWClientRebuilder**

O WoWClientRebuilder suporta **Cataclysm 4.3.4 build 15595**, baixa os dados em tempo de execução a partir dos servidores públicos de distribuição da Blizzard e verifica os arquivos produzidos.

## Configuração local

Por padrão, o instalador usa:

```text
127.0.0.1
```

No cliente:

```text
SET portal "127.0.0.1"
```

## Importante

Depois da reconstrução, use:

```text
Wow.exe
```

ou:

```text
Wow-64.exe
```

**Não execute `Launcher.exe`**, pois o launcher antigo pode tentar atualizar o cliente para outra versão.

World of Warcraft e seus arquivos pertencem aos respectivos proprietários. Este repositório não inclui nem redistribui o cliente completo.
