# Estado real do NEXUS BANK consolidado

## O que está no projeto ativo
- Aplicativo Flutter e API Node.js/Express.
- PostgreSQL com Prisma.
- Cadastro/login com hash de senha e JWT.
- Carteira de créditos virtuais NX, histórico e transferência interna NX.
- Recompensa virtual sujeita às regras e limites do backend.
- Administração protegida por papel ADMIN, concessão de NX, bloqueio/ativação, configuração e auditoria.
- Workflow GitHub Actions para gerar APK.

## Código antigo preservado
A pasta `legacy_sources/` contém cópias dos arquivos Flutter/API anteriores com painel administrativo e assistentes IA. Foram preservados para integração/referência; não são executados pelo projeto ativo e não devem ser copiados por cima dos arquivos atuais sem adaptação dos endpoints.

## Pix e dinheiro real — situação honesta
O projeto ativo NÃO realiza Pix real. Não existe credencial, contrato ou integração de uma instituição de pagamento fornecida para este projeto. Um endpoint que apenas responde sucesso seria uma simulação perigosa e foi evitado.

Para ativar Pix real será necessário selecionar e contratar um PSP/instituição autorizada e receber documentação e credenciais de sandbox/produção. Depois será preciso implementar no backend: criação de cobrança Pix, consulta de status, iniciação de transferência/saque, assinatura e validação de webhooks, idempotência, conciliação, limites, análise antifraude e trilha de auditoria. Chaves privadas ficam exclusivamente no servidor. O app deverá mostrar estados pendente/confirmado/falhou e comprovante somente após confirmação do provedor.

NX é moeda virtual interna sem valor monetário, sem saque e sem conversão para BRL/Pix. Não se pode apresentar o saldo NX como saldo bancário.

## IA
Os arquivos antigos com IA de usuário e IA administrativa foram preservados em `legacy_sources/`. A versão ativa precisa de integração dos endpoints/credenciais de IA antes de esses chats serem considerados operacionais. Chaves de IA nunca devem ser colocadas no APK.

## Antes de publicar
1. Configurar PostgreSQL e variáveis de ambiente em hospedagem segura.
2. Definir `JWT_SECRET` forte e credenciais de administrador no servidor.
3. Publicar API em HTTPS e configurar CORS para os domínios necessários.
4. Executar `npm ci`/`npm install`, `npx prisma generate`, `npx prisma db push` e `npm run db:seed` no backend.
5. Configurar o secret `API_BASE_URL` no GitHub Actions apontando para a API HTTPS.
6. Executar o workflow e revisar o resultado de `flutter analyze` e do build release.
7. Fazer testes de segurança, concorrência, recuperação de conta e operações antes de qualquer piloto.

## Estado de validação desta consolidação
A estrutura foi consolidada e a sintaxe JavaScript do backend foi verificada com `node --check`. Não foi possível compilar o Flutter/APK nem validar integração com PostgreSQL/PSP neste ambiente. Portanto, este pacote é uma base de desenvolvimento integrada, não um banco pronto para operar dinheiro real.
