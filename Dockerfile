# syntax=docker/dockerfile:1
#
# Odoo 20 image for DigitalOcean App Platform (or any Docker host).
#
# * Stage 1 builds the Python dependencies (some need a compiler: psycopg2,
#   python-ldap) into a virtualenv.
# * Stage 2 is the runtime image: system libraries, fonts, wkhtmltopdf for
#   PDF reports, the virtualenv and the Odoo sources.
#
# Configuration is done at container start by deploy/entrypoint.sh from
# environment variables (see deploy/README.md).

ARG PYTHON_VERSION=3.12

# ---------------------------------------------------------------------------
# Stage 1: build Python dependencies
# ---------------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim-bookworm AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libldap2-dev \
        libpq-dev \
        libsasl2-dev \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH

COPY requirements.txt /tmp/requirements.txt
# markdown2 is optional (markdown rendering in the mail module) and is not
# part of requirements.txt; without it Odoo logs a warning at every start.
RUN pip install --upgrade pip wheel setuptools \
    && pip install -r /tmp/requirements.txt markdown2

# ---------------------------------------------------------------------------
# Stage 2: runtime image
# ---------------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim-bookworm

ARG WKHTMLTOPDF_URL=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb
ARG WKHTMLTOPDF_SHA256=98ba0d157b50d36f23bd0dedf4c0aa28c7b0c50fcdcdc54aa5b6bbba81a3941d

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PATH=/opt/venv/bin:$PATH \
    ODOO_RC=/etc/odoo/odoo.conf

# Runtime libraries for the Python packages, fonts for reports, the
# PostgreSQL client (handy for debugging from the App Platform console) and
# wkhtmltopdf (PDF reports).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        fontconfig \
        fonts-dejavu-core \
        fonts-font-awesome \
        fonts-inconsolata \
        fonts-liberation \
        fonts-roboto-unhinted \
        gsfonts \
        libfreetype6 \
        libjpeg62-turbo \
        libldap-2.5-0 \
        libmagic1 \
        libpng16-16 \
        libpq5 \
        libsasl2-2 \
        libx11-6 \
        libxcb1 \
        libxext6 \
        libxml2 \
        libxrender1 \
        libxslt1.1 \
        postgresql-client \
        xfonts-75dpi \
        xfonts-base \
    && curl -fsSL -o /tmp/wkhtmltox.deb "${WKHTMLTOPDF_URL}" \
    && echo "${WKHTMLTOPDF_SHA256}  /tmp/wkhtmltox.deb" | sha256sum -c - \
    && apt-get install -y --no-install-recommends /tmp/wkhtmltox.deb \
    && rm -f /tmp/wkhtmltox.deb \
    && rm -rf /var/lib/apt/lists/*

# Unprivileged user; /var/lib/odoo holds sessions and the (unused) filestore.
RUN groupadd --system --gid 1001 odoo \
    && useradd --system --uid 1001 --gid odoo --home-dir /var/lib/odoo --create-home --shell /usr/sbin/nologin odoo \
    && mkdir -p /etc/odoo /opt/odoo \
    && chown -R odoo:odoo /etc/odoo /var/lib/odoo

COPY --from=builder /opt/venv /opt/venv

WORKDIR /opt/odoo
COPY --chown=odoo:odoo . /opt/odoo
RUN chmod 0755 /opt/odoo/deploy/entrypoint.sh

USER odoo

EXPOSE 8069

ENTRYPOINT ["/opt/odoo/deploy/entrypoint.sh"]
CMD ["odoo"]
