# The Faxal website: the interpreter, the built site and the Node server in one small image.
#   docker build -t faxal-site .
#   docker run -p 8080:8080 -v faxal-data:/data faxal-site        # http://localhost:8080
# Every run on the site is a separate `faxal --sandbox` process (5 second limit, no files, no network).

# --- 1. the interpreter, built from its single C file
FROM debian:bookworm-slim AS native
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY native/dist/faxal.c .
RUN gcc -O2 -std=c11 -o faxal faxal.c -lm

# --- 2. the website
FROM node:24-slim AS web
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json vite.config.ts index.html ./
COPY public public
COPY src src
COPY docs docs
COPY examples examples
RUN npx vite build

# --- 3. what runs
FROM node:24-slim
RUN useradd --system --create-home --uid 10001 faxal && mkdir /data && chown faxal /data
WORKDIR /app
COPY --from=native /src/faxal /app/faxal
COPY --from=web /src/dist /app/dist
COPY server /app/server
COPY package.json /app/
ENV NODE_ENV=production PORT=8080 FAXAL_BIN=/app/faxal DB_PATH=/data/faxal.db TRUSTED_PROXY_HOPS=1
USER faxal
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server/index.ts"]
