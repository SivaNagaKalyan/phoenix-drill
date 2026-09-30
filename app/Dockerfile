# syntax=docker/dockerfile:1.7

FROM python:3.14.7-slim-bookworm AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.14.7-slim-bookworm AS runtime
LABEL org.opencontainers.image.title="ledger" \
      org.opencontainers.image.description="Stateful demo service for the Phoenix disaster recovery drill"
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src
COPY --from=build /install /usr/local
WORKDIR /app
COPY src ./src
RUN groupadd --system --gid 10001 ledger \
 && useradd --system --uid 10001 --gid ledger --no-create-home ledger
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["uvicorn", "ledger.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
