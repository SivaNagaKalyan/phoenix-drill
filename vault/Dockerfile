# Backup vault: a small S3-compatible server built from a pinned PyPI package.
# Built locally instead of pulled, so the drill never depends on a third party
# keeping a container image published (see docs/findings.md, finding 6).
FROM python:3.12.6-slim-bookworm
RUN pip install --no-cache-dir "moto[server]==5.0.16" \
 && useradd --system --uid 10001 --no-create-home vault
USER 10001
EXPOSE 9000
ENTRYPOINT ["moto_server", "-H", "0.0.0.0", "-p", "9000"]
