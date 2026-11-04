FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY prisma ./prisma
RUN npx prisma generate && npm prune --omit=dev
COPY src ./src
ENV NODE_ENV=production
EXPOSE 3000
CMD ["npm", "start"]
