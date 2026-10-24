FROM node:20-alpine

WORKDIR /app

# Salin package.json & package-lock.json terlebih dahulu untuk pemanfaatan cache layer Docker
COPY package*.json ./

# Install dependensi produksi (tanpa nodemon / devDependencies)
RUN npm ci --omit=dev

# Salin seluruh kode backend
COPY . .

# Buat direktori default untuk assets upload jika diperlukan
RUN mkdir -p /app/assets/foto_izin

# Expose port REST API Express
EXPOSE 3000

ENV NODE_ENV=production \
    PORT=3000

CMD ["node", "server.js"]
