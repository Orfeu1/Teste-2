# API NEXUS BANK

Todas as rotas de aplicação usam o prefixo `/api`. Rotas autenticadas exigem `Authorization: Bearer <JWT>`.

## Públicas

- `GET /health` - saúde do servidor e modo `VIRTUAL_TEST_ONLY`.
- `GET /api/config` - mensagens e configuração pública de recompensas.
- `POST /api/auth/register` - cadastro `{name,email,password}`.
- `POST /api/auth/login` - login `{email,password}`.

## Usuário autenticado

- `GET /api/me` - perfil atual.
- `GET /api/wallet` - saldo NX.
- `GET /api/transactions` - até 100 movimentações.
- `POST /api/transfers/internal` - `{recipientEmail,amount,description?}`; transfere apenas NX.
- `POST /api/rewards/claim` - resgate diário limitado a uma vez por usuário/dia.

## ADMIN

- `GET /api/admin/dashboard` - contagens e resumo de créditos virtuais.
- `GET /api/admin/users` - até 200 usuários e suas carteiras.
- `POST /api/admin/users/:id/credits` - `{amount,reason}`; credita NX fictício.
- `PATCH /api/admin/users/:id/status` - `{isActive:boolean}`.
- `PATCH /api/admin/config` - `{dailyReward,rewardsEnabled,welcomeMessage,bannerTitle}`.
- `GET /api/admin/audit` - últimos 100 eventos administrativos.

## Unidade

`amount` e `balance` são inteiros de NX, não centavos de real. Nenhuma rota faz Pix, saque ou depósito real. Não altere o significado de NX para sugerir dinheiro resgatável.
