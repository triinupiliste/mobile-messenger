FROM node:18-alpine
WORKDIR /app
# ffmpeg is used to compress videos server-side after upload (see video.util.ts).
RUN apk add --no-cache ffmpeg
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
EXPOSE 5000
CMD ["npm", "start"]