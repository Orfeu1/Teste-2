import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { PrismaClient } from '@prisma/client';

const db = new PrismaClient();

async function main() {
  const name = process.env.ADMIN_NAME?.trim();
  const email = process.env.ADMIN_EMAIL?.trim().toLowerCase();
  const password = process.env.ADMIN_PASSWORD;
  const initialCredits = Number(process.env.INITIAL_ADMIN_VIRTUAL_CREDITS ?? 100000);

  if (!name || !email || !password || password.length < 14) {
    throw new Error('Configure ADMIN_NAME, ADMIN_EMAIL e ADMIN_PASSWORD (mínimo 14 caracteres).');
  }
  if (!Number.isSafeInteger(initialCredits) || initialCredits < 0 || initialCredits > 100000000) {
    throw new Error('INITIAL_ADMIN_VIRTUAL_CREDITS inválido.');
  }

  const passwordHash = await bcrypt.hash(password, 12);
  const existing = await db.user.findUnique({ where: { email } });
  if (existing) {
    await db.user.update({ where: { id: existing.id }, data: { name, role: 'ADMIN', isActive: true } });
    await db.wallet.upsert({ where: { userId: existing.id }, create: { userId: existing.id, balance: 0 }, update: {} });
    console.log('Administrador existente promovido/ativado. Saldo não foi alterado.');
  } else {
    await db.user.create({
      data: {
        name, email, passwordHash, role: 'ADMIN',
        wallet: { create: { balance: initialCredits } },
        receivedTransactions: { create: { type: 'ADMIN_CREDIT', amount: initialCredits, description: 'Saldo inicial de demonstração - moedas virtuais NX' } }
      }
    });
    console.log(`Administrador criado com ${initialCredits} créditos virtuais de teste.`);
  }
  await db.appConfig.upsert({ where: { id: 'main' }, create: { id: 'main' }, update: {} });
}

main().catch((error) => { console.error(error); process.exitCode = 1; })
  .finally(async () => db.$disconnect());
