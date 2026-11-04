import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { Prisma, PrismaClient } from '@prisma/client';

const db = new PrismaClient();
const PORT = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET || '';
if (JWT_SECRET.length < 32) throw new Error('JWT_SECRET precisa ter pelo menos 32 caracteres.');

const app = express();
app.disable('x-powered-by');
app.use(helmet());
const allowedOrigins = (process.env.CORS_ORIGIN || '').split(',').map((v) => v.trim()).filter(Boolean);
app.use(cors({ origin: allowedOrigins.length ? allowedOrigins : false }));
app.use(express.json({ limit: '20kb' }));

const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 10, standardHeaders: 'draft-7', legacyHeaders: false });
const writeLimiter = rateLimit({ windowMs: 60 * 1000, limit: 20, standardHeaders: 'draft-7', legacyHeaders: false });
const registerSchema = z.object({
  name: z.string().trim().min(2).max(80),
  email: z.string().trim().email().max(180),
  password: z.string().min(10).max(100)
});
const loginSchema = z.object({ email: z.string().trim().email().max(180), password: z.string().min(1).max(100) });
const transferSchema = z.object({
  recipientEmail: z.string().trim().email().max(180),
  amount: z.number().int().positive().max(1000000),
  description: z.string().trim().max(120).optional()
});
const adminCreditSchema = z.object({ amount: z.number().int().positive().max(1000000), reason: z.string().trim().min(3).max(120) });
const configSchema = z.object({
  dailyReward: z.number().int().min(0).max(10000),
  rewardsEnabled: z.boolean(),
  welcomeMessage: z.string().trim().min(1).max(240),
  bannerTitle: z.string().trim().min(1).max(80)
});

const safeUser = (user) => ({ id: user.id, name: user.name, email: user.email, role: user.role });
const tokenFor = (user) => jwt.sign(
  { sub: user.id }, JWT_SECRET,
  { expiresIn: process.env.JWT_EXPIRES_IN || '2h', issuer: 'nexus-bank', audience: 'nexus-app' }
);
const dayKey = () => new Date().toISOString().slice(0, 10);

async function auth(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) return res.status(401).json({ error: 'Faça login para continuar.' });
    const payload = jwt.verify(header.slice(7), JWT_SECRET, { issuer: 'nexus-bank', audience: 'nexus-app' });
    const user = await db.user.findUnique({ where: { id: payload.sub } });
    if (!user || !user.isActive) return res.status(401).json({ error: 'Conta indisponível.' });
    req.user = user;
    next();
  } catch {
    return res.status(401).json({ error: 'Sessão inválida ou expirada. Entre novamente.' });
  }
}
function admin(req, res, next) {
  if (req.user?.role !== 'ADMIN') return res.status(403).json({ error: 'Acesso exclusivo do administrador.' });
  next();
}
async function ensureConfig() {
  return db.appConfig.upsert({ where: { id: 'main' }, create: { id: 'main' }, update: {} });
}

app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'NEXUS BANK API', mode: 'VIRTUAL_TEST_ONLY' }));

app.post('/api/auth/register', authLimiter, async (req, res, next) => {
  try {
    const data = registerSchema.parse(req.body);
    const email = data.email.toLowerCase();
    const passwordHash = await bcrypt.hash(data.password, 12);
    const user = await db.user.create({
      data: { name: data.name, email, passwordHash, wallet: { create: { balance: 0 } } }
    });
    res.status(201).json({ token: tokenFor(user), user: safeUser(user) });
  } catch (error) { next(error); }
});

app.post('/api/auth/login', authLimiter, async (req, res, next) => {
  try {
    const data = loginSchema.parse(req.body);
    const user = await db.user.findUnique({ where: { email: data.email.toLowerCase() } });
    if (!user || !user.isActive || !(await bcrypt.compare(data.password, user.passwordHash))) {
      return res.status(401).json({ error: 'E-mail ou senha inválidos.' });
    }
    res.json({ token: tokenFor(user), user: safeUser(user) });
  } catch (error) { next(error); }
});

app.get('/api/config', async (_req, res, next) => {
  try {
    const config = await ensureConfig();
    res.json({ dailyReward: config.dailyReward, rewardsEnabled: config.rewardsEnabled,
      welcomeMessage: config.welcomeMessage, bannerTitle: config.bannerTitle,
      currencyCode: 'NX', currencyLabel: 'MOEDAS VIRTUAIS SEM VALOR MONETÁRIO' });
  } catch (error) { next(error); }
});

app.get('/api/me', auth, (req, res) => res.json({ user: safeUser(req.user) }));

app.get('/api/wallet', auth, async (req, res, next) => {
  try {
    const wallet = await db.wallet.findUnique({ where: { userId: req.user.id } });
    if (!wallet) return res.status(404).json({ error: 'Carteira não encontrada.' });
    res.json({ balance: wallet.balance, currencyCode: 'NX', currencyLabel: 'MOEDAS VIRTUAIS' });
  } catch (error) { next(error); }
});

app.get('/api/transactions', auth, async (req, res, next) => {
  try {
    const rows = await db.transaction.findMany({
      where: { OR: [{ senderId: req.user.id }, { receiverId: req.user.id }] },
      orderBy: { createdAt: 'desc' }, take: 100,
      include: { sender: { select: { name: true, email: true } }, receiver: { select: { name: true, email: true } } }
    });
    res.json(rows.map((row) => ({
      id: row.id, type: row.type, amount: row.amount, description: row.description,
      createdAt: row.createdAt,
      direction: row.receiverId === req.user.id ? 'IN' : 'OUT',
      otherParty: row.receiverId === req.user.id ? row.sender?.email : row.receiver?.email
    })));
  } catch (error) { next(error); }
});

app.post('/api/transfers/internal', auth, writeLimiter, async (req, res, next) => {
  try {
    const data = transferSchema.parse(req.body);
    const email = data.recipientEmail.toLowerCase();
    if (email === req.user.email) return res.status(400).json({ error: 'Não é possível transferir para si mesmo.' });
    const recipient = await db.user.findUnique({ where: { email } });
    if (!recipient || !recipient.isActive) return res.status(404).json({ error: 'Destinatário não encontrado.' });

    await db.$transaction(async (tx) => {
      const senderWallet = await tx.wallet.findUnique({ where: { userId: req.user.id } });
      const recipientWallet = await tx.wallet.findUnique({ where: { userId: recipient.id } });
      if (!senderWallet || !recipientWallet) throw new Error('WALLET_NOT_FOUND');
      const debit = await tx.wallet.updateMany({
        where: { id: senderWallet.id, balance: { gte: data.amount } },
        data: { balance: { decrement: data.amount } }
      });
      if (debit.count !== 1) throw new Error('INSUFFICIENT_VIRTUAL_BALANCE');
      await tx.wallet.update({ where: { id: recipientWallet.id }, data: { balance: { increment: data.amount } } });
      await tx.transaction.create({ data: {
        type: 'TRANSFER', amount: data.amount,
        description: data.description || 'Transferência interna de moedas virtuais',
        senderId: req.user.id, receiverId: recipient.id
      } });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    res.status(201).json({ status: 'completed', amount: data.amount, currencyCode: 'NX' });
  } catch (error) {
    if (error.message === 'INSUFFICIENT_VIRTUAL_BALANCE') return res.status(409).json({ error: 'Saldo virtual insuficiente.' });
    if (error.message === 'WALLET_NOT_FOUND') return res.status(404).json({ error: 'Carteira não encontrada.' });
    next(error);
  }
});

app.post('/api/rewards/claim', auth, writeLimiter, async (req, res, next) => {
  try {
    const config = await ensureConfig();
    if (!config.rewardsEnabled || config.dailyReward <= 0) return res.status(403).json({ error: 'O gerador de moedas está desativado.' });
    const key = dayKey();
    await db.$transaction(async (tx) => {
      await tx.rewardClaim.create({ data: { userId: req.user.id, dayKey: key } });
      await tx.wallet.update({ where: { userId: req.user.id }, data: { balance: { increment: config.dailyReward } } });
      await tx.transaction.create({ data: {
        type: 'REWARD', amount: config.dailyReward,
        description: 'Recompensa diária - moedas virtuais sem valor monetário', receiverId: req.user.id
      } });
    });
    res.status(201).json({ status: 'claimed', amount: config.dailyReward, currencyCode: 'NX' });
  } catch (error) {
    if (error.code === 'P2002') return res.status(409).json({ error: 'Você já resgatou sua recompensa de hoje.' });
    next(error);
  }
});

app.get('/api/admin/dashboard', auth, admin, async (_req, res, next) => {
  try {
    const [users, activeUsers, walletTotals, transactions, config] = await Promise.all([
      db.user.count(), db.user.count({ where: { isActive: true } }),
      db.wallet.aggregate({ _sum: { balance: true } }), db.transaction.count(), ensureConfig()
    ]);
    res.json({ users, activeUsers, virtualCreditsInCirculation: walletTotals._sum.balance || 0,
      transactions, config: { dailyReward: config.dailyReward, rewardsEnabled: config.rewardsEnabled,
        welcomeMessage: config.welcomeMessage, bannerTitle: config.bannerTitle } });
  } catch (error) { next(error); }
});

app.get('/api/admin/users', auth, admin, async (_req, res, next) => {
  try {
    const users = await db.user.findMany({
      select: { id: true, name: true, email: true, role: true, isActive: true, createdAt: true,
        wallet: { select: { balance: true } } },
      take: 200, orderBy: { createdAt: 'desc' }
    });
    res.json(users);
  } catch (error) { next(error); }
});

app.post('/api/admin/users/:id/credits', auth, admin, writeLimiter, async (req, res, next) => {
  try {
    const data = adminCreditSchema.parse(req.body);
    const target = await db.user.findUnique({ where: { id: req.params.id } });
    if (!target) return res.status(404).json({ error: 'Usuário não encontrado.' });
    await db.$transaction(async (tx) => {
      await tx.wallet.update({ where: { userId: target.id }, data: { balance: { increment: data.amount } } });
      await tx.transaction.create({ data: {
        type: 'ADMIN_CREDIT', amount: data.amount,
        description: `Crédito virtual administrativo: ${data.reason}`, receiverId: target.id
      } });
      await tx.auditLog.create({ data: {
        adminId: req.user.id, targetUserId: target.id, action: 'GRANT_VIRTUAL_CREDITS',
        details: { amount: data.amount, reason: data.reason }
      } });
    });
    res.status(201).json({ status: 'credited', amount: data.amount, currencyCode: 'NX' });
  } catch (error) { next(error); }
});

app.patch('/api/admin/users/:id/status', auth, admin, async (req, res, next) => {
  try {
    const data = z.object({ isActive: z.boolean() }).parse(req.body);
    if (req.params.id === req.user.id && !data.isActive) return res.status(400).json({ error: 'O administrador não pode desativar a própria conta.' });
    const target = await db.user.update({ where: { id: req.params.id }, data: { isActive: data.isActive } });
    await db.auditLog.create({ data: { adminId: req.user.id, targetUserId: target.id,
      action: data.isActive ? 'ACTIVATE_USER' : 'DEACTIVATE_USER', details: { isActive: data.isActive } } });
    res.json({ id: target.id, isActive: target.isActive });
  } catch (error) { next(error); }
});

app.patch('/api/admin/config', auth, admin, async (req, res, next) => {
  try {
    const data = configSchema.parse(req.body);
    const config = await db.appConfig.upsert({ where: { id: 'main' }, create: { id: 'main', ...data }, update: data });
    await db.auditLog.create({ data: { adminId: req.user.id, action: 'UPDATE_APP_CONFIG', details: data } });
    res.json({ dailyReward: config.dailyReward, rewardsEnabled: config.rewardsEnabled,
      welcomeMessage: config.welcomeMessage, bannerTitle: config.bannerTitle });
  } catch (error) { next(error); }
});

app.get('/api/admin/audit', auth, admin, async (_req, res, next) => {
  try {
    const rows = await db.auditLog.findMany({ orderBy: { createdAt: 'desc' }, take: 100,
      include: { admin: { select: { email: true } } } });
    res.json(rows.map((row) => ({ id: row.id, action: row.action, targetUserId: row.targetUserId,
      details: row.details, createdAt: row.createdAt, adminEmail: row.admin.email })));
  } catch (error) { next(error); }
});

app.use((error, _req, res, _next) => {
  if (error instanceof z.ZodError) return res.status(400).json({ error: 'Dados inválidos.', details: error.issues });
  if (error.code === 'P2002') return res.status(409).json({ error: 'Este cadastro já existe ou a operação já foi realizada.' });
  if (error.code === 'P2025') return res.status(404).json({ error: 'Registro não encontrado.' });
  console.error(error);
  res.status(500).json({ error: 'Erro interno. Consulte os logs do servidor.' });
});

const server = app.listen(PORT, () => console.log(`NEXUS BANK API ouvindo na porta ${PORT} (somente carteira virtual de teste).`));
async function shutdown() {
  server.close(async () => { await db.$disconnect(); process.exit(0); });
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
