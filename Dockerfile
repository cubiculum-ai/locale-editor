FROM swift:6.0-jammy
RUN apt-get update && apt-get install -y --no-install-recommends locales python3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
COPY . .
RUN swift build
CMD ["bash", "Scripts/check-linux.sh"]
