# syntax=docker/dockerfile:1.7

# Pin to a specific digest-free tag; Trivy's config scan flags `:latest`.
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Create an unprivileged user so the container does not run as root.
RUN groupadd --system --gid 1001 appgroup \
    && useradd  --system --uid 1001 --gid appgroup --home-dir /app --shell /sbin/nologin appuser

COPY --chown=appuser:appgroup app.py ./

USER appuser

EXPOSE 8000

# Lightweight stdlib-only health check so we don't pull in curl/wget.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=2).status==200 else 1)"

CMD ["python", "app.py"]
