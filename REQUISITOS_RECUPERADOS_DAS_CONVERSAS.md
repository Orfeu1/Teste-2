# NEXUS BANK — requisitos recuperados

Este documento reúne os requisitos mencionados nas conversas anteriores e separa o que existe no código do que ainda exige implementação ou integração externa.

## Identidade e preservação
- Nome correto: **NEXUS BANK**.
- Preservar os códigos antigos e manter cópias em `legacy_sources/`; não apagar versões anteriores.
- App Android em Flutter, API Node.js/Express, PostgreSQL/Prisma e build APK via GitHub Actions.

## Experiência do usuário
- Cadastro, login, sessão persistente e contas individuais.
- Carteira, histórico e transferências entre contas NEXUS.
- Assistente IA para usuários e IA separada no painel administrativo.
- Painel administrativo restrito ao papel ADMIN para gerir usuários, configurações, recursos e campanhas.
- Acesso à mesma conta em outros dispositivos com autenticação segura.
- Comprovantes e trilha de auditoria das operações.

## Moedas
- Não limitar a arquitetura ao NX.
- Preparar suporte a múltiplas moedas/ativos, com código, nome, casas decimais e carteira/histórico separados por ativo.
- Distinguir rigorosamente moedas virtuais internas de moedas fiduciárias reais.
- NX e outros créditos criados no app são virtuais, não são dinheiro, não têm saque nem conversão garantida.
- Conversão entre BRL, USD, EUR e outras moedas exige cotação externa atualizada e deve ser apenas informativa até existir serviço financeiro autorizado e liquidação real.
- O saldo inicial administrativo de 100.000 foi pedido como crédito virtual NX; deve ser concedido uma única vez e auditado.

## Pix e transferências externas
- Requisito: Pix por chave, QR Code, recebimento, envio para outros bancos, comprovantes e histórico.
- **Não está implementado neste pacote**: Pix real exige contrato e integração com instituição/PSP participante, credenciais, homologação, liquidação, conciliação e controles antifraude. Não simular sucesso nem permitir Pix sem fundos efetivamente disponíveis.
- Transferência interna de créditos virtuais não é Pix.

## Regras financeiras e segurança
- Não implementar a ideia de depositar R$ 1 e sacar R$ 50 como dinheiro real: isso não é uma operação legítima sem fundos/financiamento.
- Não criar saldo real fictício ou saque com saldo negativo.
- Senhas com hash, JWT, autorização por função, validação, limites de requisição, transações atômicas e auditoria.
- Chaves de IA e credenciais financeiras somente no servidor, nunca no APK.

## Estado verificado deste pacote
- O ZIP contém backend Node/Express + Prisma/PostgreSQL, app Flutter, workflow de build e versões antigas preservadas.
- Backend atual tem cadastro/login, carteira virtual NX, transferência interna NX, recompensa diária e endpoints administrativos.
- O código antigo com painel/IA está preservado em `legacy_sources`; isso não significa que todas as funções antigas estejam integradas à versão ativa.
- Pix real, transferências bancárias reais, carteira fiduciária multimoeda, conversão cambial executável e integração efetiva das duas IAs **não devem ser considerados concluídos**.
- Não foi possível compilar APK nem executar testes de integração Flutter/PostgreSQL neste ambiente. O workflow do GitHub é o caminho para validar a compilação depois de configurar e hospedar a API.

## Próximas implementações técnicas
1. Modelar `Currency/Asset`, carteiras por usuário e ativo, e `currencyCode` nas transações; migrar saldos NX existentes sem perda.
2. Atualizar API e Flutter para selecionar ativo, consultar saldo e transferir somente entre carteiras do mesmo ativo.
3. Adicionar cotação cambial informativa com fonte, timestamp e aviso de que não é liquidação.
4. Integrar IA do usuário e IA administrativa com provedores configurados no servidor.
5. Integrar Pix somente após escolha e homologação do parceiro financeiro.
6. Testar migrações, concorrência, idempotência, autorização, Flutter analyze e build release.
