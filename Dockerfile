# Open Analytics node roles (api, gateway, collector, realtime, worker, migrate, web) on Railway.
# One Dockerfile, one image per role: BASE is the upstream role image pinned by digest, ROLE picks the entrypoint branch.
# Upstream's compose shares key files through volumes and starts services in dependency order; a template can do neither,
# so keys are derived from one seed variable and every role waits for the migrate service in its entrypoint.
# upstream: OpenLabs-so/openanalytics
ARG BASE
FROM ${BASE}
ARG ROLE
ARG FRONT=0
USER root
RUN if [ "$FRONT" = "1" ]; then \
      apt-get update && apt-get install -y --no-install-recommends nginx && rm -rf /var/lib/apt/lists/* \
      && rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/*; \
    fi
COPY oa/ /opt/oa/
RUN chmod +x /opt/oa/entrypoint.sh
ENV OA_ROLE=${ROLE}
USER node
ENTRYPOINT ["/opt/oa/entrypoint.sh"]
CMD []
