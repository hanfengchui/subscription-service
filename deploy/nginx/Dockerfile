FROM node:18-alpine AS frontend-build

ARG VITE_APP_BASE_URL=/
ARG VITE_API_BASE_URL=

WORKDIR /app

COPY apps/frontend/package.json ./
RUN npm install

COPY apps/frontend ./
RUN VITE_APP_BASE_URL=${VITE_APP_BASE_URL} VITE_API_BASE_URL=${VITE_API_BASE_URL} npm run build

FROM nginx:alpine

COPY deploy/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=frontend-build /app/dist /usr/share/nginx/html

EXPOSE 80
