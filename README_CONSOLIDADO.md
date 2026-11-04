# NEXUS BANK — pacote consolidado

Este pacote reúne a versão ativa, documentação e fontes antigas recuperadas. O arquivo `REQUISITOS_RECUPERADOS_DAS_CONVERSAS.md` registra os pedidos anteriores e o estado real de cada recurso.

**Importante:** não é um banco autorizado nem está pronto para movimentar dinheiro real. A versão ativa trabalha com NX virtual e transferências internas. Pix real e contas fiduciárias multimoeda dependem de integração financeira externa e ainda não estão implementados.

- `flutter_app/`: aplicativo Flutter ativo.
- `backend/`: API Node.js/Express + Prisma.
- `legacy_sources/`: versões antigas preservadas, inclusive interfaces e scripts anteriores.
- `docs/`: documentação técnica e limites da versão.
- `.github/workflows/`: build APK via GitHub Actions, após configurar a URL da API.
