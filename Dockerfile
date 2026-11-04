FROM node:20-alpine

RUN apk add --no-cache openssl

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY schema.prisma ./schema.prisma

RUN npx prisma generate --schema=./schema.prisma

COPY server.js ./server.js
COPY seed-admin.js ./seed-admin.js

RUN npm prune --omit=dev

ENV NODE_ENV=production

EXPOSE 3000

CMD ["npm", "start"]