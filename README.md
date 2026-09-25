# Pariz Cataclysm 4.3.4 Repack

<p align="center">
  <strong>Servidor World of Warcraft Cataclysm 4.3.4 — Build 15595</strong>
</p>

<p align="center">
  Baseado no TrinityCore / The Cataclysm Preservation Project
</p>

<p align="center">
  <a href="https://github.com/ronilsondesouza045-beep/Pariz-Cataclysm-434-Repack/releases/tag/v1.0.0">
    <img src="https://img.shields.io/badge/Release-v1.0.0-2ea44f?style=for-the-badge" alt="Release v1.0.0">
  </a>
  <a href="https://github.com/ronilsondesouza045-beep/Pariz-Cataclysm-434-Repack/releases/download/v1.0.0/Pariz-Cataclysm-434-Repack-v1.0.0.zip">
    <img src="https://img.shields.io/badge/Download-Repack-0969da?style=for-the-badge" alt="Download Repack">
  </a>
</p>

---

## Sobre o projeto

O **Pariz Cataclysm 4.3.4 Repack** é um ambiente de servidor preparado e testado para **World of Warcraft: Cataclysm 4.3.4 build 15595**.

A base utilizada é o **The Cataclysm Preservation Project / TrinityCore**.

| Item | Informação |
|---|---|
| Expansão | Cataclysm |
| Versão | 4.3.4 |
| Build | 15595 |
| Core | TrinityCore / Cataclysm Preservation Project |
| Banco de dados | MySQL 8.1 portable |
| OpenSSL | 3.x |
| Plataforma | Windows x64 |
| Release | v1.0.0 |

---

## Download

### Servidor pronto

**[Baixar Pariz Cataclysm 4.3.4 Repack v1.0.0](https://github.com/ronilsondesouza045-beep/Pariz-Cataclysm-434-Repack/releases/download/v1.0.0/Pariz-Cataclysm-434-Repack-v1.0.0.zip)**

**[Abrir página da Release](https://github.com/ronilsondesouza045-beep/Pariz-Cataclysm-434-Repack/releases/tag/v1.0.0)**

### Código-fonte

O código-fonte correspondente desta versão também está disponível na Release:

Pariz-Cataclysm-434-Source-v1.0.0.zip

---

<!-- PARIZ-CLIENTE-1CLIQUE-START -->

## Cliente Cataclysm 4.3.4 — download fácil

**[🎮 BAIXAR INSTALADOR DO CLIENTE 4.3.4 BUILD 15595](https://github.com/ronilsondesouza045-beep/Pariz-Cataclysm-434-Repack/releases/download/v1.0.0/Pariz-Cliente-Cataclysm-434-Installer.zip)**

Baixe o ZIP, extraia e execute:

`	ext
INSTALAR-CLIENTE-CATACLYSM-434.cmd
`

Não é necessário copiar comandos do PowerShell manualmente. O instalador abre uma interface e prepara o cliente no computador da própria pessoa.

> Requisitos: Windows 10/11 64-bit, internet, aproximadamente 20 GB livres e permissão de administrador.

O link original do **WoWClientRebuilder** e o guia detalhado continuam disponíveis em [CLIENTE.md](CLIENTE.md).

<!-- PARIZ-CLIENTE-1CLIQUE-END -->

## Cliente Cataclysm 4.3.4

O cliente do jogo **não está incluído no repack**.

Versão esperada:

`	ext
World of Warcraft: Cataclysm
Version: 4.3.4
Build: 15595
`

Para reconstruir um cliente compatível:

**[WoWClientRebuilder](https://github.com/mangostools/WoWClientRebuilder)**

No ambiente de teste local, o cliente foi configurado com:

`	ext
SET portal "127.0.0.1"
`

Arquivo:

`	ext
WTF\Config.wtf
`

Mais detalhes: **[CLIENTE.md](CLIENTE.md)**

---

## Instalação rápida

Extraia o repack em uma pasta com permissão de escrita.

Execute nesta ordem:

`	ext
1-START-MYSQL.cmd
2-START-AUTH.cmd
3-START-WORLD.cmd
`

Depois abra o cliente Cataclysm 4.3.4 build 15595.

---

## Estrutura do repack

`	ext
REPACK-CATACLYSMO-434
|
+-- 1-START-MYSQL.cmd
+-- 2-START-AUTH.cmd
+-- 3-START-WORLD.cmd
|
+-- Server
|   +-- authserver.exe
|   +-- worldserver.exe
|   +-- legacy.dll
|   +-- libcrypto-3-x64.dll
|   +-- libssl-3-x64.dll
|
+-- MySQL
+-- ClientTools
+-- Docs
+-- Logs
`

> Dados derivados do cliente, como DBC, maps, vmaps e mmaps, não são redistribuídos publicamente neste repositório.

---

## Correções aplicadas

### OpenSSL 3 / RC4

Foi corrigido o crash do worldserver relacionado ao uso de RC4 com OpenSSL 3.

O ambiente utiliza o provider legado:

`	ext
legacy.dll
`

Os scripts de inicialização configuram:

`	ext
OPENSSL_MODULES
`

para que o provider seja carregado corretamente.

### Conexão

Ambiente testado com:

`	ext
Auth port : 3724
World port: 8085
Realm     : 127.0.0.1
Build     : 15595
`

### Map Extractor

O source utilizado recebeu correção para um problema encontrado durante a enumeração de arquivos DBC/DB2 no mapextractor.

### VMAPS / MMAPS

O ambiente foi preparado para iniciar com os recursos relacionados a VMAPS/MMAPS desativados enquanto esses dados não estiverem disponíveis localmente.

---

## Administrador

Por segurança, **nenhuma senha administrativa universal é publicada**.

Depois de iniciar o servidor, crie sua própria conta administrativa pelo console do worldserver.

Exemplo:

`	ext
account create ADMIN_LOCAL SUA_SENHA_FORTE
account set gmlevel ADMIN_LOCAL 3 -1
`

Veja: **[ADMIN-SETUP.md](ADMIN-SETUP.md)**

---

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [CLIENTE.md](CLIENTE.md) | Cliente Cataclysm 4.3.4 build 15595 |
| [DOWNLOADS.md](DOWNLOADS.md) | Links de download |
| [ADMIN-SETUP.md](ADMIN-SETUP.md) | Criação de administrador |
| [CHANGELOG.md](CHANGELOG.md) | Alterações da versão |
| [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) | Créditos e componentes externos |

---

## Projeto-base

**The Cataclysm Preservation Project / TrinityCore**

https://github.com/The-Cataclysm-Preservation-Project/TrinityCore

Commit-base utilizado:

`	ext
06890421bdde257952f958d75c35460fc6478fcb
`

---

## Créditos e licença

A base do servidor deriva do trabalho do **TrinityCore** e do **The Cataclysm Preservation Project**.

A ferramenta indicada para reconstrução do cliente é o **WoWClientRebuilder / MaNGOS Tools**.

Consulte o arquivo COPYING presente no código-fonte correspondente para os termos de licença aplicáveis.

**World of Warcraft**, **Cataclysm**, Blizzard Entertainment e marcas relacionadas pertencem aos respectivos proprietários.

Este projeto não é afiliado, patrocinado ou endossado pela Blizzard Entertainment.

---

<p align="center">
  <strong>Pariz Cataclysm 4.3.4 — Build 15595</strong>
</p>