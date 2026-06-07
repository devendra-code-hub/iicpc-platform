FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY src/ ./src/
COPY proto/ ./proto/
EXPOSE 50051
CMD ["node", "src/ingester.js"]
