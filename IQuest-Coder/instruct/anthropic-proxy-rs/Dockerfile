# syntax=docker/dockerfile:1.7

############################
# Build stage
############################
FROM rust:1.84 AS builder
WORKDIR /src

ARG PROXY_REF=main

# rust:1.84 已自带 git
RUN rustc --version && cargo --version

# 拉源码
RUN git clone https://github.com/m0n0x41d/anthropic-proxy-rs.git . \
  && git checkout ${PROXY_REF}

# ⚠️ 不使用 target cache，避免 BuildKit 吃掉产物
RUN cargo build --release

############################
# Runtime stage
############################
FROM gcr.io/distroless/cc-debian12:nonroot

# anthropic-proxy-rs 的 bin 名是确定的
COPY --from=builder /src/target/release/anthropic-proxy /usr/local/bin/anthropic-proxy

EXPOSE 3000
USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/anthropic-proxy"]
