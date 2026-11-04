# NEXUS BANK - projeto inicial completo de carteira virtual

Este repositório contém um aplicativo Flutter, uma API Node.js/Express, banco PostgreSQL via Prisma, painel administrativo dentro do app e fluxo GitHub Actions para gerar APK.

> **Limite essencial:** esta versão é uma carteira de **moedas virtuais NX de teste**. NX não é real, não é depósito, não é investimento, não pode ser convertido em reais e não pode ser sacado por Pix. Não existe promessa de transformar R$ 1 em R$ 50 nem de pagar retiradas sem fundos. A API não tem rotas de depósito bancário ou saque Pix.

## Estrutura

- `flutter_app/`: app Android Flutter (login, cadastro, carteira, transferências internas de NX, recompensa diária, histórico e painel ADMIN).
- `backend/`: API, autenticação JWT, hash de senha, PostgreSQL, transferências atômicas de NX, recompensas com limite diário, gestão administrativa e auditoria.
- `.github/workflows/build-apk.yml`: compila APK release e publica o arquivo como artefato do GitHub Actions.
- `docs/`: especificação funcional e endpoints.

## O que funciona nesta base

1. Cadastro e login de usuário com senha armazenada em hash bcrypt.
2. Carteira separada por usuário, com saldo inteiro de moedas NX.
3. Transferência interna de moedas NX com verificação de saldo na transação do banco de dados.
4. Recompensa virtual diária com bloqueio de resgate repetido no mesmo dia.
5. Administrador configurável por variáveis privadas do servidor; ao criar a conta pela primeira vez, recebe 100.000 NX de teste por padrão (ajustável).
6. Painel ADMIN no app para listar usuários, creditar moedas virtuais, ativar/desativar contas e mudar banner, mensagem e recompensa diária.
7. Registros de auditoria para créditos e mudanças administrativas.
8. Token JWT armazenado no armazenamento seguro do Android.

## O que NÃO está incluído

- Pix real, saque, depósito, cartão, boleto, Open Finance, crédito ou qualquer conexão com saldo de banco.
- Conversão de NX em BRL ou saque dos NX.
- Licença/autorização para operar como instituição financeira ou de pagamento.
- Infraestrutura de produção auditada, monitoramento, antifraude e certificações.

Uma operação com dinheiro real exige contrato e integração com uma instituição/provedor autorizado, conta de liquidação, regras de saldo lastreado, conciliação, controles antifraude/PLD, atendimento, privacidade e avaliação jurídica/regulatória. Não basta alterar o texto do app ou criar um endpoint Pix.

## Configuração do backend

É necessário publicar a pasta `backend` em um host que execute Node.js 20+ e fornecer PostgreSQL. O host deve disponibilizar URL HTTPS pública para o app.

1. Copie `backend/.env.example` para `.env` no ambiente do servidor (não envie o `.env` ao GitHub).
2. Configure `DATABASE_URL` com sua conexão PostgreSQL.
3. Configure `JWT_SECRET` com uma chave aleatória de no mínimo 32 caracteres. Exemplo para gerar localmente: `openssl rand -hex 32`.
4. Configure `ADMIN_NAME`, `ADMIN_EMAIL` e `ADMIN_PASSWORD`; use uma senha forte, única e com 14 ou mais caracteres.
5. Instale dependências: `npm install`.
6. Gere o cliente e crie as tabelas: `npx prisma generate` e `npx prisma db push`.
7. Crie o primeiro administrador: `npm run db:seed`.
8. Inicie com `npm start`.
9. Teste `https://SUA-API/health`. A resposta deve indicar `status: ok`.

**Importante:** `INITIAL_ADMIN_VIRTUAL_CREDITS=100000` concede NX fictício apenas quando a conta ADMIN é criada pela primeira vez. Rodar o seed novamente não soma os créditos outra vez.

## Gerar o APK pelo GitHub usando o celular

Depois que o backend estiver publicado e o endereço HTTPS funcionar:

1. Envie a pasta deste projeto para um repositório GitHub.
2. No repositório, abra **Settings > Secrets and variables > Actions > New repository secret**.
3. Nome: `API_BASE_URL`. Valor: URL HTTPS do servidor terminando em `/api`, por exemplo `https://api.seudominio.com/api`.
4. Abra **Actions > NEXUS BANK - Build APK > Run workflow**.
5. Quando a execução terminar com sucesso, abra a execução e baixe o artefato `nexus-bank-apk`.

O workflow executa `flutter analyze` antes da compilação. Se a análise ou compilação falhar, consulte o log da etapa indicada; não ignore os erros.

## Antes de instalar em aparelhos de outras pessoas

- Configure domínio HTTPS e CORS para qualquer painel web adicional.
- Revise política de privacidade, termos, canal de suporte e tratamento de dados pessoais.
- Faça teste com contas distintas e tentativas de saldo insuficiente, transferência duplicada, resgate repetido e conta desativada.
- Troque/remova credenciais de teste e proteja o administrador com MFA antes de qualquer piloto.
- Nunca peça que clientes depositem dinheiro acreditando que NX é dinheiro ou que será possível sacar.

## Testes de sintaxe disponíveis neste ambiente

O arquivo Node foi verificado com `node --check`. Este ambiente não tem Flutter/Dart nem PostgreSQL configurados, então a compilação Android, o Prisma contra um banco real e os fluxos integrados precisam ser validados no GitHub Actions/servidor antes de distribuir o APK.
