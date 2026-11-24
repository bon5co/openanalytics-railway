# Open Analytics ClickHouse on Railway: upstream image plus IPv6 listen (Railway's private network is IPv6) and the volume fixes.
# upstream: OpenLabs-so/openanalytics
ARG BASE
FROM ${BASE}
COPY listen.xml /etc/clickhouse-server/config.d/railway-listen.xml
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh
# Baked, not a template variable: a literal variable publishes as a required blank. "::/0" covers IPv4-mapped clients too.
ENV OA_CLICKHOUSE_ALLOWED_NETWORK="::/0"
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
