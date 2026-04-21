# syntax=docker/dockerfile:1
FROM node:20-bullseye AS builder

WORKDIR /app

# Build dependencies inkl. unzip fuer Bun-Installer
RUN apt-get update -y && apt-get install -y \
    openssl \
    python3 \
    python3-pip \
    build-essential \
    g++ \
    make \
    unzip \
    curl

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

COPY package.json ./
COPY bun.lock* ./
COPY db ./db
COPY drizzle ./drizzle
COPY drizzle.config.ts ./

ENV PYTHON=/usr/bin/python3

RUN npm install better-sqlite3 --build-from-source --legacy-peer-deps
RUN bun install --frozen-lockfile
RUN bun add sharp

COPY . .

# Build-Time ARGs fuer Next.js Public-ENV
# Diese Werte werden in den Client-JS-Bundle eingebacken
ARG NEXT_PUBLIC_BASE_URL=http://localhost:3000
ARG NEXT_PUBLIC_PASSKEY_RP_ID=localhost
ARG NEXT_PUBLIC_PASSKEY_ORIGIN=http://localhost:3000
ENV NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL
ENV NEXT_PUBLIC_PASSKEY_RP_ID=$NEXT_PUBLIC_PASSKEY_RP_ID
ENV NEXT_PUBLIC_PASSKEY_ORIGIN=$NEXT_PUBLIC_PASSKEY_ORIGIN

RUN bun run build

# Production image
FROM node:20-bullseye-slim AS runner

WORKDIR /app

ENV NODE_ENV=production

RUN apt-get update -y && apt-get install -y \
    openssl \
    python3 \
    build-essential \
    g++ \
    make \
    curl \
    unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN groupadd --system --gid 1001 nodejs && \
    useradd --system --uid 1001 --gid nodejs nextjs && \
    mkdir -p /app/data && \
    chmod 777 /app/data && \
    chown -R nextjs:nodejs /app

COPY --from=builder --chown=nextjs:nodejs /app/package.json ./
COPY --from=builder --chown=nextjs:nodejs /app/bun.lock* ./
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/db ./db
COPY --from=builder --chown=nextjs:nodejs /app/drizzle ./drizzle
COPY --from=builder --chown=nextjs:nodejs /app/drizzle.config.ts ./drizzle.config.ts
COPY --from=builder --chown=nextjs:nodejs /app/next.config.mjs ./
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next

EXPOSE 3000

CMD ["sh", "-c", "npx drizzle-kit push --force && bun run start"]
