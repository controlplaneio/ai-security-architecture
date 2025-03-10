# Stage 1: Build
FROM debian:bookworm as builder

RUN \
  DEBIAN_FRONTEND=noninteractive \
    apt update && apt install --assume-yes --no-install-recommends \
      curl \
      ca-certificates \
      wget \
  \
  && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/sigoden/aichat/releases/download/v0.19.0/aichat-v0.19.0-x86_64-unknown-linux-musl.tar.gz && \
    tar -xvf aichat-*.tar.gz && \
    mv aichat /bin/aichat && \
    chmod +x /bin/aichat && \
    rm -rf aichat-*.tar.gz

# Stage 2: Final
FROM alpine:latest

RUN adduser -D -u 1000 aichatuser

WORKDIR /app

COPY --from=builder /bin/aichat /app/aichat
RUN chown -R aichatuser:aichatuser /app

USER aichatuser

EXPOSE 8080

CMD ["./aichat", "--serve", "0.0.0.0:8080"]


