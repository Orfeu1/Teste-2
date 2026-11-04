# NEXUS BANK - Especificação do projeto

**Versão:** 1.0.0 - **Data:** 04/11/2026

## 1. Objetivo

Construir o NEXUS BANK como aplicativo Android com cadastro, login, carteira por usuário, histórico, transferências internas, recompensas virtuais e painel administrativo protegido. A primeira entrega usa moedas virtuais NX exclusivamente para testes e experiência dentro do app.

## 2. Requisitos recebidos e tratamento

| Pedido | Tratamento no projeto |
|---|---|
| Nome NEXUS BANK | Nome do produto e identidade do aplicativo. A comunicação deve dizer que esta versão é uma carteira virtual, não uma instituição financeira autorizada. |
| Depositar R$ 1 e sacar R$ 50 | Não implementado. Não existe forma sustentável ou legítima de multiplicar dinheiro assim. Para qualquer saque real, é necessário saldo efetivamente disponível, lastro, regras claras e provedor/instituição autorizada. |
| Painel administrativo exclusivo | Implementado como área ADMIN protegida pela API, com criação inicial via variáveis privadas do servidor; permite controlar usuários, mensagens, recompensa e créditos virtuais. |
| Pix mesmo sem saldo | Não implementado. Um Pix de saída exige fundos disponíveis ou crédito formalmente aprovado e financiado. Criar um Pix sem cobertura seria uma promessa falsa e poderia causar prejuízo. |
| Gerador de moedas virtuais | Implementado como recompensa diária de NX, configurável pelo administrador e limitada a um resgate por usuário por dia. NX não é dinheiro e não pode ser sacado. |
| Admin com saldo 100.000 | O primeiro administrador recebe 100.000 NX fictícios por padrão, uma única vez na criação da conta. O valor pode ser alterado por variável de ambiente. |
| Projeto para gerar APK | Workflow GitHub Actions incluído. Antes de compilar, é preciso publicar a API e o PostgreSQL, configurar o secret `API_BASE_URL` com HTTPS terminando em `/api` e executar o workflow. |

## 3. Aplicativo

- Tela de entrada e criação de conta.
- Armazenamento seguro do token de sessão no Android.
- Carteira com saldo em NX.
- Transferência entre usuários NEXUS com validação de saldo.
- Resgate de recompensa diária virtual.
- Histórico de entradas e saídas.
- Navegação administrativa visível apenas para conta com papel ADMIN.

## 4. API e dados

Tecnologia: Node.js 20+, Express, Prisma e PostgreSQL. Senhas são armazenadas com hash bcrypt. A API usa JWT com validade configurável, validação de entrada, cabeçalhos de segurança, limitação de tentativas de autenticação e operações atômicas no banco.

Tabelas: `User`, `Wallet`, `Transaction`, `RewardClaim`, `AppConfig` e `AuditLog`. O saldo NX usa números inteiros para evitar problemas de arredondamento. As transferências são feitas dentro de transação de banco; o débito só ocorre quando o saldo é suficiente.

## 5. Painel administrativo

- Visão geral de usuários, usuários ativos, quantidade de NX em circulação e operações.
- Listagem de contas e respectivos saldos virtuais.
- Concessão de NX com motivo obrigatório.
- Ativação e desativação de contas.
- Edição do título, mensagem de boas-vindas, valor da recompensa e ativação do gerador.
- Auditoria persistente das alterações administrativas relevantes.

As credenciais do primeiro administrador são fornecidas no servidor por variáveis de ambiente. Não há senha universal nem senha de administrador gravada no aplicativo.

## 6. Limites de dinheiro real

Esta versão não contém Pix, depósito, saque, cartão, boleto, crédito, investimento ou conexão bancária. NX é uma unidade virtual sem valor monetário. Não deve ser anunciada como dinheiro, rendimento, saldo sacável ou promessa de retorno.

Para oferecer dinheiro real, será necessário contratar uma instituição/provedor autorizado, formalizar a estrutura jurídica e operacional, implementar contas e liquidação reais, conciliação, controles contra fraude e lavagem de dinheiro, proteção de dados, suporte e auditoria. A implementação depende de contratos, aprovação do parceiro e avaliação jurídica/regulatória. A geração de APK, sozinha, não habilita movimentação financeira.

## 7. Publicação e compilação

1. Criar PostgreSQL no provedor escolhido.
2. Publicar `backend/` em hospedagem Node.js com HTTPS.
3. Configurar `DATABASE_URL`, `JWT_SECRET`, `ADMIN_NAME`, `ADMIN_EMAIL` e `ADMIN_PASSWORD` no servidor.
4. Executar `npm install`, `npx prisma generate`, `npx prisma db push` e `npm run db:seed`.
5. Confirmar `https://SEU_HOST/health` respondendo `status: ok`.
6. Fazer upload do projeto para GitHub.
7. Adicionar secret `API_BASE_URL`, com URL HTTPS da API terminando em `/api`.
8. Abrir Actions e executar **NEXUS BANK - Build APK**.
9. Baixar o artefato `nexus-bank-apk` após conclusão com sucesso.

## 8. Verificação desta entrega

Foi verificada a sintaxe JavaScript dos arquivos Node com `node --check` e o balanceamento de delimitadores do arquivo Dart. O ambiente de criação não possui Flutter/Dart nem PostgreSQL configurados; portanto, o APK não foi compilado aqui e a integração real entre API e banco ainda precisa ser executada no ambiente de hospedagem/GitHub. O workflow inclui `flutter analyze` e compilação release para revelar eventuais erros restantes.
