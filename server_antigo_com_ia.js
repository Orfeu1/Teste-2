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
if (!JWT_SECRET || JWT_SECRET.length < 32) throw new Error('JWT_SECRET deve ter pelo menos 32 caracteres.');

app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN === '*' ? '*' : (process.env.CORS_ORIGIN || '').split(',').filter(Boolean) }));
app.use(express.json({ limit: '16kb' }));

const cents = n => Number(n) / 100;
const tokenFor = user => jwt.sign({ sub: user.id }, JWT_SECRET, { expiresIn: '2h' });

function auth(req, res, next) {
  const raw = req.headers.authorization || '';
  if (!raw.startsWith('Bearer ')) return res.status(401).json({ erro: 'Faça login novamente.' });
  try {
    req.userId = jwt.verify(raw.slice(7), JWT_SECRET).sub;
    prisma.user.findUnique({ where: { id: req.userId }, select: { blocked: true } }).then(user => {
      if (!user || user.blocked) return res.status(403).json({ erro: 'Conta bloqueada ou inexistente.' });
      next();
    }).catch(next);
  } catch { res.status(401).json({ erro: 'Sessão inválida ou expirada.' }); }
}

async function requireAdmin(req, res, next) {
  try {
    const user = await prisma.user.findUnique({ where: { id: req.userId }, select: { role: true, blocked: true } });
    if (!user || user.blocked) return res.status(403).json({ erro: 'Conta sem permissão ou bloqueada.' });
    if (user.role !== 'admin') return res.status(403).json({ erro: 'Acesso exclusivo do administrador.' });
    next();
  } catch (e) { next(e); }
}

async function getSettings() {
  const rows = await prisma.appSetting.findMany();
  const settings = Object.fromEntries(rows.map(row => [row.key, row.value]));
  return { appName: settings.appName ?? 'Minha Carteira', maintenance: settings.maintenance ?? false,
    maintenanceMessage: settings.maintenanceMessage ?? 'Estamos realizando uma manutenção. Tente novamente em breve.',
    bannerText: settings.bannerText ?? '', features: settings.features ?? { rewards: true, assistant: true, history: true } };
}


app.use('/api', async (req, res, next) => {
  if (req.path === '/health' || req.path.startsWith('/auth/')) return next();
  try {
    const settings = await getSettings();
    if (!settings.maintenance) return next();
    const raw = req.headers.authorization || '';
    if (raw.startsWith('Bearer ')) {
      try {
        const payload = jwt.verify(raw.slice(7), JWT_SECRET);
        const user = await prisma.user.findUnique({ where: { id: payload.sub }, select: { role: true } });
        if (user?.role === 'admin') return next();
      } catch {}
    }
    return res.status(503).json({ erro: settings.maintenanceMessage });
  } catch (e) { next(e); }
});

app.get('/api/health', (_req, res) => res.json({ status: 'ok' }));
app.get('/api/config', async (_req, res, next) => { try { const s = await getSettings(); res.json({ appName: s.appName, bannerText: s.bannerText, maintenance: s.maintenance, features: s.features }); } catch (e) { next(e); } });

app.post('/api/auth/register', async (req, res, next) => {
  try {
    const parsed = z.object({
      nome: z.string().trim().min(2).max(80),
      email: z.string().trim().email().max(160),
      senha: z.string().min(10).max(72)
    }).safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ erro: 'Nome, e-mail ou senha inválidos. A senha precisa ter 10 caracteres.' });
    const { nome, email, senha } = parsed.data;
    const user = await prisma.user.create({
      data: { name: nome, email: email.toLowerCase(), passwordHash: await bcrypt.hash(senha, 12), wallet: { create: {} } },
      select: { id: true, name: true, email: true }
    });
    res.status(201).json({ mensagem: 'Conta criada.', usuario: user });
  } catch (e) {
    if (e.code === 'P2002') return res.status(409).json({ erro: 'E-mail já cadastrado.' });
    next(e);
  }
});

app.post('/api/auth/login', async (req, res, next) => {
  try {
    const parsed = z.object({ email: z.string().email(), senha: z.string().min(1).max(72) }).safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ erro: 'E-mail ou senha inválidos.' });
    const user = await prisma.user.findUnique({ where: { email: parsed.data.email.toLowerCase() } });
    if (!user || !(await bcrypt.compare(parsed.data.senha, user.passwordHash))) return res.status(401).json({ erro: 'E-mail ou senha inválidos.' });
    if (user.blocked) return res.status(403).json({ erro: 'Esta conta está bloqueada. Procure o suporte.' });
    res.json({ token: tokenFor(user), nome: user.name, role: user.role });
  } catch (e) { next(e); }
});

app.get('/api/wallet', auth, async (req, res, next) => {
  try {
    const wallet = await prisma.wallet.findUnique({ where: { userId: req.userId } });
    if (!wallet) return res.status(404).json({ erro: 'Carteira não encontrada.' });
    res.json({ saldo: cents(wallet.balance), moeda: 'BRL', atualizadoEm: wallet.updatedAt });
  } catch (e) { next(e); }
});

app.get('/api/transactions', auth, async (req, res, next) => {
  try {
    const rows = await prisma.transaction.findMany({ where: { userId: req.userId }, orderBy: { createdAt: 'desc' }, take: 100 });
    res.json({ transactions: rows.map(x => ({
      id: x.id, tipo: x.type, valor: cents(x.amount), descricao: x.description,
      status: x.status, data: x.createdAt
    })) });
  } catch (e) { next(e); }
});

app.post('/api/rewards/claim', auth, async (req, res, next) => {
  const campaignId = String(req.body?.campaignId || '');
  if (!campaignId || campaignId.length > 80) return res.status(400).json({ erro: 'Campanha inválida.' });
  try {
    const result = await prisma.$transaction(async tx => {
      const campaign = await tx.rewardCampaign.findUnique({ where: { id: campaignId } });
      if (!campaign?.active) throw Object.assign(new Error('Campanha indisponível.'), { status: 404 });
      const already = await tx.rewardClaim.findUnique({ where: { userId_campaignId: { userId: req.userId, campaignId } } });
      if (already) throw Object.assign(new Error('Você já solicitou esta recompensa.'), { status: 409 });
      const reserve = await tx.rewardCampaign.updateMany({
        where: { id: campaignId, active: true, budgetCents: { gte: campaign.rewardCents } },
        data: { budgetCents: { decrement: campaign.rewardCents } }
      });
      if (reserve.count !== 1) throw Object.assign(new Error('Orçamento da campanha esgotado.'), { status: 409 });
      await tx.rewardClaim.create({ data: { userId: req.userId, campaignId, amount: campaign.rewardCents } });
      await tx.wallet.update({ where: { userId: req.userId }, data: { balance: { increment: campaign.rewardCents } } });
      await tx.transaction.create({ data: {
        userId: req.userId, type: 'reward', amount: campaign.rewardCents,
        description: `Recompensa: ${campaign.name}`, reference: `reward_${randomUUID()}`
      }});
      const wallet = await tx.wallet.findUnique({ where: { userId: req.userId } });
      return { amount: campaign.rewardCents, balance: wallet.balance };
    });
    res.json({ mensagem: 'Recompensa creditada conforme as regras da campanha.', valorCreditado: cents(result.amount), novoSaldo: cents(result.balance) });
  } catch (e) {
    if (e.status) return res.status(e.status).json({ erro: e.message });
    if (e.code === 'P2002') return res.status(409).json({ erro: 'Recompensa já solicitada.' });
    next(e);
  }
});


// Rotas administrativas: permissão sempre validada no banco.
app.get('/api/admin/overview', auth, requireAdmin, async (_req, res, next) => {
  try {
    const [users, blocked, transactions, settings, campaigns] = await Promise.all([
      prisma.user.count(), prisma.user.count({ where: { blocked: true } }), prisma.transaction.count(),
      getSettings(), prisma.rewardCampaign.findMany({ orderBy: { id: 'asc' } })
    ]);
    res.json({ users, blocked, transactions, settings, campaigns: campaigns.map(c => ({ id: c.id, name: c.name, reward: cents(c.rewardCents), budget: cents(c.budgetCents), active: c.active })) });
  } catch (e) { next(e); }
});
app.get('/api/admin/users', auth, requireAdmin, async (_req, res, next) => {
  try { res.json({ users: await prisma.user.findMany({ orderBy: { createdAt: 'desc' }, take: 200, select: { id: true, name: true, email: true, role: true, blocked: true, createdAt: true } }) }); }
  catch (e) { next(e); }
});
app.patch('/api/admin/users/:id/block', auth, requireAdmin, async (req, res, next) => {
  try {
    const target = await prisma.user.findUnique({ where: { id: req.params.id } });
    if (!target) return res.status(404).json({ erro: 'Usuário não encontrado.' });
    if (target.role === 'admin') return res.status(403).json({ erro: 'Não é permitido bloquear uma conta administradora por este painel.' });
    const parsed = z.boolean().safeParse(req.body?.blocked);
    if (!parsed.success) return res.status(400).json({ erro: 'Informe blocked como verdadeiro ou falso.' });
    await prisma.user.update({ where: { id: target.id }, data: { blocked: parsed.data } });
    res.json({ mensagem: parsed.data ? 'Usuário bloqueado.' : 'Usuário desbloqueado.' });
  } catch (e) { next(e); }
});
app.put('/api/admin/settings', auth, requireAdmin, async (req, res, next) => {
  try {
    const parsed = z.object({ appName: z.string().trim().min(2).max(50).optional(), maintenance: z.boolean().optional(),
      maintenanceMessage: z.string().trim().max(300).optional(), bannerText: z.string().trim().max(300).optional(),
      features: z.object({ rewards: z.boolean().optional(), assistant: z.boolean().optional(), history: z.boolean().optional() }).optional() }).strict().safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ erro: 'Configuração inválida.' });
    for (const [key, value] of Object.entries(parsed.data)) await prisma.appSetting.upsert({ where: { key }, create: { key, value }, update: { value } });
    res.json({ mensagem: 'Configurações salvas.', settings: await getSettings() });
  } catch (e) { next(e); }
});
app.post('/api/admin/ai/chat', auth, requireAdmin, async (req, res) => {
  const parsed = z.object({ message: z.string().trim().min(1).max(3000) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ erro: 'Envie uma mensagem de até 3000 caracteres.' });
  const message = parsed.data.message;
  if (!process.env.ADMIN_AI_API_KEY || !process.env.ADMIN_AI_MODEL) return res.json({ mode: 'admin-ai-not-configured', reply: 'Sou a IA privada do painel. Minha conexão ainda não foi configurada. Defina ADMIN_AI_API_KEY e ADMIN_AI_MODEL no servidor. Posso ajudar a planejar melhorias, revisar configurações e explicar relatórios, mas não altero dados diretamente.' });
  try {
    const base = (process.env.ADMIN_AI_BASE_URL || 'https://api.openai.com/v1').replace(/\/$/, '');
    const response = await fetch(`${base}/chat/completions`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${process.env.ADMIN_AI_API_KEY}` },
      body: JSON.stringify({ model: process.env.ADMIN_AI_MODEL, max_tokens: Number(process.env.ADMIN_AI_MAX_OUTPUT_TOKENS || 700), messages: [
        { role: 'system', content: 'Você é a IA PRIVADA DO PAINEL ADMINISTRATIVO, diferente da IA dos usuários. Responda em português brasileiro. Ajude o administrador a planejar melhorias, interpretar indicadores, revisar configurações e preparar especificações. Este chat não executa alterações: nunca diga que as realizou. Nunca peça senhas, tokens, chaves de API ou dados pessoais completos. Diferencie fatos, hipóteses e sugestões.' },
        { role: 'user', content: message }] }) });
    if (!response.ok) return res.status(502).json({ erro: 'A IA administrativa está temporariamente indisponível.' });
    const data = await response.json(); const reply = data?.choices?.[0]?.message?.content;
    res.json({ mode: 'admin-ai', reply: typeof reply === 'string' && reply.trim() ? reply : 'Não consegui formular uma resposta.' });
  } catch (e) { console.error('Admin AI error:', e.message); res.status(502).json({ erro: 'Falha ao conectar à IA administrativa.' }); }
});

const fallbackReply = (message) => {
  const m = message.toLowerCase();
  if (m.includes('pix') || m.includes('saque')) return 'Os saques Pix ainda não estão habilitados. Eles só serão liberados depois de integrar uma instituição de pagamento e concluir os testes de segurança.';
  if (m.includes('senha') || m.includes('código')) return 'Nunca compartilhe sua senha, código SMS ou código de autenticação. A equipe de suporte não deve pedir esses dados.';
  if (m.includes('recompensa') || m.includes('50') || m.includes('dinheiro')) return 'As recompensas dependem das regras e do orçamento real disponível na campanha. Não existe promessa de multiplicação garantida do dinheiro.';
  return 'Posso ajudar a explicar cadastro, carteira, histórico, recompensas e segurança. Para dúvidas sobre uma movimentação específica, consulte o histórico e procure o suporte oficial do aplicativo.';
};

app.post('/api/ai/chat', auth, async (req, res) => {
  const parsed = z.object({ message: z.string().trim().min(1).max(1200) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ erro: 'Escreva uma pergunta de até 1200 caracteres.' });
  const message = parsed.data.message;

  // Sem chave configurada, o app continua com respostas locais de ajuda.
  if (!process.env.AI_API_KEY || !process.env.AI_MODEL) {
    return res.json({ reply: fallbackReply(message), mode: 'help-fallback' });
  }

  try {
    const base = (process.env.AI_BASE_URL || 'https://api.openai.com/v1').replace(/\/$/, '');
    const response = await fetch(`${base}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${process.env.AI_API_KEY}` },
      body: JSON.stringify({
        model: process.env.AI_MODEL,
        max_tokens: Number(process.env.AI_MAX_OUTPUT_TOKENS || 350),
        messages: [
          { role: 'system', content: 'Você é o assistente de ajuda do aplicativo Carteira. Responda em português brasileiro, com clareza e empatia. Explique somente cadastro, uso do app, carteira, histórico, recompensas e segurança. Nunca solicite senhas, códigos SMS, tokens ou chaves Pix. Nunca prometa lucro, rendimento, multiplicação de dinheiro ou saque garantido. Não execute nem autorize pagamentos, transferências ou alterações de saldo. Se perguntarem sobre saque Pix, informe que depende da ativação oficial da instituição de pagamento. Não dê aconselhamento financeiro personalizado.' },
          { role: 'user', content: message }
        ]
      })
    });
    if (!response.ok) {
      console.error('AI provider status:', response.status);
      return res.json({ reply: fallbackReply(message), mode: 'help-fallback' });
    }
    const data = await response.json();
    const reply = data?.choices?.[0]?.message?.content;
    res.json({ reply: typeof reply === 'string' && reply.trim() ? reply : fallbackReply(message), mode: 'ai' });
  } catch (e) {
    console.error('AI request failed:', e.message);
    res.json({ reply: fallbackReply(message), mode: 'help-fallback' });
  }
});

// Pix permanece deliberadamente desativado até existir integração real com PSP.
app.post('/api/pix/withdrawals', auth, (_req, res) => res.status(501).json({
  erro: 'Saque Pix ainda não habilitado. É necessária integração com instituição de pagamento, webhooks assinados e conciliação.'
}));

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ erro: 'Erro interno. Tente novamente mais tarde.' });
});

app.listen(PORT, () => console.log(`Carteira API ativa na porta ${PORT}`));
process.on('SIGINT', async () => { await prisma.$disconnect(); process.exit(0); });
