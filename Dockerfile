# syntax=docker/dockerfile:1.7

FROM elixir:1.17.3-otp-27-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/bin:$PATH

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    openssl \
    pkg-config \
    ripgrep \
    tini \
  && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.95.0 \
  && mix local.hex --force \
  && mix local.rebar --force \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

FROM base AS dev
WORKDIR /workspace/treedb/apps/api
ENV MIX_ENV=dev \
    TREEDB_DATA_DIR=/var/lib/treedb
EXPOSE 4000
ENTRYPOINT ["tini", "--"]
CMD ["mix", "phx.server"]

FROM base AS build
WORKDIR /workspace/treedb
ENV MIX_ENV=prod \
    TREEDB_DATA_DIR=/var/lib/treedb
COPY . .
WORKDIR /workspace/treedb/apps/api
RUN --mount=type=cache,target=/usr/local/cargo/registry \
  --mount=type=cache,target=/usr/local/cargo/git \
  --mount=type=cache,target=/workspace/treedb/target \
  --mount=type=cache,target=/workspace/treedb/apps/api/deps \
  mix deps.get --only prod \
  && mix compile \
  && cargo build --release -p treedb_git --bin treedb_git_worker \
  && mix release \
  && cp ../../target/release/treedb_git_worker _build/prod/rel/treedb/bin/treedb_git_worker

FROM debian:bookworm-slim AS runtime-libs
RUN apt-get update \
  && apt-get install -y --no-install-recommends busybox-static ca-certificates git libtinfo6 \
  && groupadd --gid 65532 nonroot \
  && useradd --uid 65532 --gid 65532 --no-create-home --shell /usr/sbin/nologin nonroot \
  && mkdir -p /runtime/var/lib/treedb \
  && chown -R nonroot:nonroot /runtime/var/lib/treedb \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

FROM runtime-libs AS prod
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TREEDB_DATA_DIR=/var/lib/treedb \
    PHX_SERVER=true
COPY --from=runtime-libs --chown=nonroot:nonroot /runtime/var/lib/treedb /var/lib/treedb
WORKDIR /app
COPY --from=build --chown=nonroot:nonroot /workspace/treedb/apps/api/_build/prod/rel/treedb ./
USER nonroot:nonroot
EXPOSE 4000
CMD ["/app/bin/treedb", "start"]
