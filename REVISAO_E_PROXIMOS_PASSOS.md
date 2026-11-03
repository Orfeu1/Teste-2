# Revisão técnica — Carteira + Assistente IA

## Correções aplicadas nesta revisão
- `backend/prisma/seed.js`: permite preparar o banco com campanha zerada; antes o seed falhava com os valores padrão do `.env.example`.
- O seed não repõe o orçamento nem reativa uma campanha existente quando executado novamente. Isso evita recriar saldo promocional já consumido.
- `.github/workflows/build-apk.yml`: a compilação agora exige `API_BASE_URL` configurada e HTTPS. Antes podia gerar um APK apontando para um endereço fictício.

## Pendente antes de uso real
- Hospedar PostgreSQL e backend HTTPS.
- Definir `JWT_SECRET` forte (32+ caracteres), `ADMIN_EMAIL` e `ADMIN_PASSWORD` (16+ caracteres) no ambiente seguro do backend.
- Configurar `AI_API_KEY`/`AI_MODEL` e, separadamente, `ADMIN_AI_API_KEY`/`ADMIN_AI_MODEL`.
- Fazer testes de integração e revisão de segurança, incluindo limitação de tentativas, recuperação/verificação de conta, auditoria, backups e LGPD.
- Integrar um PSP para Pix, com webhooks assinados e conciliação. Saque continua desativado intencionalmente.
- A IA administrativa atual é consultiva: não edita arquivos nem publica mudanças no aplicativo. Alterações de código precisam passar por um fluxo controlado de revisão e implantação.

## Como gerar o APK
1. Envie a pasta do projeto ao GitHub mantendo `.github/workflows/build-apk.yml`.
2. Em Settings > Secrets and variables > Actions > Variables, crie `API_BASE_URL` com a URL HTTPS real terminada em `/api`.
3. Abra Actions > Build Android APK > Run workflow.
4. Baixe o artefato `carteira-apk` quando a execução terminar com sucesso.

## Limite desta revisão
As alterações acima são correções estáticas do projeto. Não foi possível validar login, banco, provedor de IA ou APK em execução porque dependem de serviços e credenciais externos ainda não configurados.
