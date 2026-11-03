# Projeto Carteira + Assistente IA

Projeto inicial integrado, organizado para trabalhar pelo celular e compilar APK em nuvem.

## O que já está no projeto
- App Flutter: cadastro, login, carteira, histórico, recompensas e chat de ajuda com IA.
- Backend Node.js/Express: autenticação JWT, senhas com hash, saldo em centavos, histórico e campanhas com orçamento limitado.
- PostgreSQL + Prisma.
- Endpoint de IA configurável por provedor compatível com a API de Chat Completions.
- Workflow GitHub Actions para compilar APK na nuvem.

## Atenção: o que ainda NÃO está ativo
- Não existe transferência Pix real nesta versão. O endpoint de saque fica desativado de propósito até integrar uma instituição de pagamento/PSP.
- A IA precisa de uma chave de API configurada no servidor. Nunca coloque essa chave dentro do app Flutter.
- A campanha de recompensa só pode distribuir valores que estejam realmente reservados. Não prometa rendimento ou multiplicação garantida.
- Este é um projeto inicial para testes, não está pronto para custodiar dinheiro real ou operar publicamente.

## 1. Backend
Requisitos: Node.js 20+ e PostgreSQL.

Entre em `backend/`, copie `.env.example` para `.env` e configure:
- `DATABASE_URL`
- `JWT_SECRET` (32 caracteres ou mais)
- `AI_API_KEY`, `AI_BASE_URL` e `AI_MODEL` se quiser ativar a IA real.
- Configure `WELCOME_REWARD_CENTS` e `WELCOME_CAMPAIGN_BUDGET_CENTS` somente depois de reservar fundos reais para a campanha; os valores de exemplo começam em zero.

Instale e inicie:

```bash
npm install
npx prisma generate
npx prisma migrate dev --name init
npm run db:seed
npm run dev
```

Teste `GET /api/health`.

Crie conta pela tela do app. O app chama `POST /api/auth/register`.

## 2. App Flutter
Entre em `flutter_app/`.

Instale Flutter e dependências num ambiente Flutter:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://SEU_BACKEND
```

No Android Emulator local, normalmente a API local do computador é `http://10.0.2.2:3000/api`.
No celular físico, `localhost` é o próprio celular; use o IP da máquina na mesma rede ou, para produção, um domínio HTTPS.

## 3. Gerar APK sem computador usando GitHub Actions
O projeto inclui `.github/workflows/build-apk.yml`.

1. Crie um repositório no GitHub pelo navegador do celular.
2. Envie o conteúdo desta pasta para o repositório, mantendo as pastas e o caminho `.github/workflows/build-apk.yml`.
3. No GitHub, abra a aba **Actions** e habilite workflows se solicitado.
4. Abra **Build Android APK** e toque em **Run workflow** (ou faça um commit para disparar automaticamente).
5. Quando terminar, abra a execução e baixe o artefato `carteira-apk`.

Configure a variável `API_BASE_URL` em Settings > Secrets and variables > Actions > Variables, com a URL HTTPS pública do backend. Sem backend hospedado, o APK pode abrir, mas login, carteira e IA não funcionarão online.

## Painel administrativo e IA privada
- O usuário recebe o papel `user` por padrão; o cadastro público nunca permite escolher papel administrativo.
- Configure `ADMIN_EMAIL` e `ADMIN_PASSWORD` no ambiente do backend antes de executar `npm run db:seed`. A senha inicial do administrador precisa ter 16 caracteres ou mais. O seed cria/atualiza essa conta como `admin`.
- O painel aparece após o login da conta administradora. As rotas `/api/admin/*` verificam a função no banco de dados.
- A IA do painel usa `ADMIN_AI_BASE_URL`, `ADMIN_AI_API_KEY` e `ADMIN_AI_MODEL`, independentes de `AI_*` da IA de atendimento. Ela é um chat consultivo e não executa mudanças diretamente.
- O painel inicial inclui indicadores, bloqueio/desbloqueio de usuários, nome do app, aviso/banner e modo de manutenção. Recursos novos que não existam no código ainda exigem desenvolvimento e publicação de nova versão.
- Para aplicar o novo schema, execute `npx prisma db push` (ou crie uma migration revisada) antes de iniciar o backend.

## Segurança antes de produção
Adicionar rate limiting persistente, verificação de e-mail/telefone, recuperação de senha, proteção contra abuso, logs de auditoria, monitoramento, backups, política de privacidade/LGPD, testes de concorrência, revisão de segurança e integração de PSP com webhooks assinados e conciliação. Configure CORS apenas para origens necessárias e use HTTPS.
