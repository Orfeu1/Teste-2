
FROM node:20-alpine

WORKDIR /app

COPY backend/package*.json ./

RUN npm install

COPY backend/prisma ./prisma

RUN npx prisma generate && npm prune --omit=dev

COPY backend/src ./src

ENV NODE_ENV=production

EXPOSE 3000

CMD ["npm", "start"]

