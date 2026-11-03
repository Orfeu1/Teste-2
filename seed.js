import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';
const prisma = new PrismaClient();
const reward = BigInt(process.env.WELCOME_REWARD_CENTS || '0');
const budget = BigInt(process.env.WELCOME_CAMPAIGN_BUDGET_CENTS || '0');
// Valores zero significam campanha ainda não configurada.
if (reward === 0n && budget === 0n) {
  console.log('Campanha welcome não criada: orçamento ainda não configurado.');
} else {
  if (reward <= 0n || budget < reward) throw new Error('A recompensa deve ser positiva e o orçamento deve cobri-la.');
  // Nunca repõe orçamento consumido nem reativa campanha desativada ao rodar seed.
  await prisma.rewardCampaign.upsert({
    where: { id: 'welcome' },
    update: {},
    create: { id: 'welcome', name: 'Campanha de boas-vindas', rewardCents: reward, budgetCents: budget, active: true }
  });
  console.log('Campanha welcome verificada.');
}
const adminEmail = process.env.ADMIN_EMAIL?.trim().toLowerCase();
const adminPassword = process.env.ADMIN_PASSWORD;
if (adminEmail && adminPassword) {
  if (adminPassword.length < 16) throw new Error('ADMIN_PASSWORD precisa ter pelo menos 16 caracteres.');
  const passwordHash = await bcrypt.hash(adminPassword, 12);
  await prisma.user.upsert({ where: { email: adminEmail }, update: { role: 'admin', blocked: false, passwordHash },
    create: { name: 'Administrador', email: adminEmail, passwordHash, role: 'admin', wallet: { create: {} } } });
  console.log(`Administrador configurado: ${adminEmail}`);
} else {
  console.log('ADMIN_EMAIL/ADMIN_PASSWORD não definidos; nenhum administrador foi criado.');
}
await prisma.$disconnect();
