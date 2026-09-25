# Changelog

## v1.0.0

### Servidor

- Build Cataclysm 4.3.4.15595 configurado.
- Authserver funcionando.
- Worldserver funcionando.
- MySQL portable configurado.
- Banco auth configurado.
- Banco characters configurado.
- Banco world configurado.
- Banco hotfixes configurado.

### Conexao

- Realm configurado para ambiente local.
- Porta de auth: 3724.
- Porta do worldserver: 8085.
- Configuracao de build 15595.

### OpenSSL

- Corrigido crash relacionado a RC4 no OpenSSL 3.
- Provider legacy habilitado.
- legacy.dll incluÃ­do no ambiente do servidor.
- OPENSSL_MODULES configurado pelos scripts de inicializacao.

### Client / launcher

- Ambiente testado com cliente 4.3.4.15595.
- Cliente nao incluido neste repositorio publico.

### Dados

- DBC/maps/vmaps/mmaps extraidos do cliente nao sao redistribuidos.
- Administrador deve gerar seus proprios dados quando necessario.

### SeguranÃ§a

- Nenhuma senha administrativa universal e publicada.
- Administrador deve criar suas proprias credenciais.