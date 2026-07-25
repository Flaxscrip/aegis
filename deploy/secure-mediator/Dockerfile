FROM node:22-slim
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY src ./src
COPY seed.mjs ./
# Default: run the mediator. Override the command to run the seed (node seed.mjs <port> <host>).
CMD ["node", "src/mediator.mjs"]
