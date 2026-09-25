# Criando uma conta de administrador

Por seguranca, este projeto nao vem com uma senha de administrador publica.

Depois que o MySQL, authserver e worldserver estiverem funcionando,
use o console do worldserver.

Consulte primeiro:

\\\	ext
help account
\\\

ou no jogo, com uma conta que ja possua permissao:

\\\	ext
.help account
\\\

Os comandos utilizados pelo TrinityCore para criar uma conta e alterar o nivel GM seguem o formato:

\\\	ext
account create NOME SENHA
account set gmlevel NOME 3 -1
\\\

Exemplo:

\\\	ext
account create ADMIN_LOCAL SUA_SENHA_FORTE
account set gmlevel ADMIN_LOCAL 3 -1
\\\

Troque imediatamente \SUA_SENHA_FORTE\ por uma senha particular.

Nunca publique sua senha real no GitHub.