# =============================================================================
# record-pool web: Expo static export served by unprivileged nginx on :8080.
#   docker build -t record-pool .
#   docker build --build-arg EXPO_PUBLIC_API_URL=https://api.example.com -t record-pool .
# =============================================================================
FROM node:22.23.3-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
# Inlined into the bundle at build time. Empty = same origin as the web app.
ARG EXPO_PUBLIC_API_URL=""
ENV EXPO_PUBLIC_API_URL=$EXPO_PUBLIC_API_URL
RUN npx expo export --platform web

FROM nginxinc/nginx-unprivileged:1.29.8-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 8080
