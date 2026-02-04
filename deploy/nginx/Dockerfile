FROM node:18-alpine AS frontend-build

WORKDIR /app

COPY apps/frontend/package.json ./
RUN npm install

COPY apps/frontend ./
RUN npm run build

FROM nginx:alpine

COPY deploy/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=frontend-build /app/dist /usr/share/nginx/html

EXPOSE 80
