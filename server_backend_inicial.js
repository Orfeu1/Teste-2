import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { z } from 'zod';

const prisma = new PrismaClient();
const app = express();
const PORT = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET || JWT_SECRET.length < 32) {
  throw new Error('JWT_SECRET precisa ter pelo menos 32 caracteres.');
}

app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN === '*'
    ? '*'
    : (process.env.CORS_ORIGIN || '').split(',').filter(Boolean)
}));
app.use(express.json({ limit: '20kb' }));

function centsToNumber(cents) {
  // API retorna reais como número para compatibilidade com o Flutter atual.
  return Number(cents) / 100;
}

function signToken(user) {
  return jwt.sign({ sub: user.id }, JWT_SECRET, { expiresIn: '2h' });
}

function auth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ erro: 'Faça login novamente.' });

  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.userId = payload.sub;
    return next();
  } catch {
    return res.status(401).json({ erro: 'Sessão inválida ou expirada.' });
  }
}

const registerSchema = z.object({
  nome: z.string().trim().min(2).max(80),
  email: z.string().trim().email().max(160),
  senha: z.string().min(10).max(72)
});

const loginSchema = z.object({
  email: z.string().trim().email().max(160),
  senha: z.string().min(1).max(72)
});

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok' });
});

// Cadastro: crie a conta antes de entrar pelo Flutter.
app.post('/api/auth/register', async (req, res, next) => {
  try {
    const parsed = registerSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ erro: 'Dados inválidos. A senha deve ter ao menos 10 caracteres.' });
    }

    const { nome, email, senha } = parsed.data;
    const passwordHash = await bcrypt.hash(senha, 12);

    const user = await prisma.user.create({
      data: {
        name: nome,
        email: email.toLowerCase(),
        passwordHash,
        wallet: { create: {} }
      },
      select: { id: true, name: true, email: true }
    });

    return res.status(201).json({
      mensagem: 'Conta criada.',
      usuario: user
    });
  } catch (error) {
    if (error?.code === 'P2002') {
      return res.status(409).json({ erro: 'Este e-mail já está cadastrado.' });
    }
    return next(error);
  }
});

app.post('/api/auth/login', async (req, res, next) => {
  try {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ erro: 'E-mail ou senha inválidos.' });

    const user = await prisma.user.findUnique({
      where: { email: parsed.data.email.toLowerCase() }
    });

    const valid = user && await bcrypt.compare(parsed.data.senha, user.passwordHash);
    if (!valid) return res.status(401).json({ erro: 'E-mail ou senha inválidos.' });

    return res.json({
      token: signToken(user),
      nome: user.name
    });
  } catch (error) {
    return next(error);
  }
});

app.get('/api/wallet', auth, async (req, res, next) => {
  try {
    const wallet = await prisma.wallet.findUnique({ where: { userId: req.userId } });
    if (!wallet) return res.status(404).json({ erro: 'Carteira não encontrada.' });

    return res.json({
      saldo: centsToNumber(wallet.balance),
      moeda: 'BRL',
      atualizadoEm: wallet.updatedAt
    });
  } catch (error) {
    return next(error);
  }
});

app.get('/api/transactions', auth, async (req, res, next) => {
  try {
    const rows = await prisma.transaction.findMany({
      where: { userId: req.userId },
      orderBy: { createdAt: 'desc' },
      take: 100
    });

    return res.json({
      transactions: rows.map(row => ({
        id: row.id,
        tipo: row.type,
        valor: centsToNumber(row.amount),
        descricao: row.description,
        status: row.status,
        data: row.createdAt
      }))
    });
  } catch (error) {
    return next(error);
  }
});

// Recompensa de demonstração. O orçamento da campanha é consumido
// atomicamente junto com o crédito da carteira e o registro contábil.
app.post('/api/rewards/claim', auth, async (req, res, next) => {
  const campaignId = String(req.body?.campaignId || '');

  if (!campaignId || campaignId.length > 80) {
    return res.status(400).json({ erro: 'Campanha inválida.' });
  }

  try {
    const result = await prisma.$transaction(async tx => {
      const campaign = await tx.rewardCampaign.findUnique({
        where: { id: campaignId }
      });

      if (!campaign || !campaign.active) {
        throw Object.assign(new Error('Campanha indisponível.'), { status: 404 });
      }

      const existing = await tx.rewardClaim.findUnique({
        where: {
          userId_campaignId: {
            userId: req.userId,
            campaignId
          }
        }
      });

      if (existing) {
        throw Object.assign(new Error('Esta recompensa já foi solicitada.'), { status: 409 });
      }

      // Reserva orçamento apenas se ainda houver fundos na campanha.
      const reserved = await tx.rewardCampaign.updateMany({
        where: {
          id: campaignId,
          active: true,
          budgetCents: { gte: campaign.rewardCents }
        },
        data: {
          budgetCents: { decrement: campaign.rewardCents }
        }
      });

      if (reserved.count !== 1) {
        throw Object.assign(new Error('Orçamento de recompensas esgotado.'), { status: 409 });
      }

      await tx.rewardClaim.create({
        data: {
          userId: req.userId,
          campaignId,
          amount: campaign.rewardCents
        }
      });

      await tx.wallet.update({
        where: { userId: req.userId },
        data: { balance: { increment: campaign.rewardCents } }
      });

      await tx.transaction.create({
        data: {
          userId: req.userId,
          type: 'reward',
          amount: campaign.rewardCents,
          description: `Recompensa: ${campaign.name}`,
          reference: `reward_${randomUUID()}`
        }
      });

      const wallet = await tx.wallet.findUnique({ where: { userId: req.userId } });
      return { amount: campaign.rewardCents, balance: wallet.balance };
    });

    return res.json({
      mensagem: 'Recompensa creditada conforme as regras da campanha.',
      valorCreditado: centsToNumber(result.amount),
      novoSaldo: centsToNumber(result.balance)
    });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ erro: error.message });
    if (error?.code === 'P2002') {
      return res.status(409).json({ erro: 'Esta recompensa já foi solicitada.' });
    }
    return next(error);
  }
});

// Não simula transferência Pix. Integração real depende de um PSP/banco,
// credenciais, webhooks assinados, conciliação e validação regulatória.
app.post('/api/pix/withdrawals', auth, (_req, res) => {
  return res.status(501).json({
    erro: 'Saque Pix ainda não habilitado. Configure uma instituição de pagamento e o fluxo de conciliação antes de ativar.'
  });
});

app.use((err, _req, res, _next) => {
  console.error(err);
  return res.status(500).json({ erro: 'Erro interno. Tente novamente mais tarde.' });
});

app.listen(PORT, () => {
  console.log(`API da carteira rodando na porta ${PORT}`);
});

process.on('SIGINT', async () => {
  await prisma.$disconnect();
  process.exit(0);
});
