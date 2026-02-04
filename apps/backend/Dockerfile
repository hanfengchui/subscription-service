FROM node:18-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src
COPY config ./config

ENV NODE_ENV=production

EXPOSE 3000

CMD ["node", "src/app.js"]
