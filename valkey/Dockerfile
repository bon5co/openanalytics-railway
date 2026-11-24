# Open Analytics Valkey on Railway. Upstream picks durable (queue) or LRU (realtime) behaviour from OA_VALKEY_CONF;
# a literal template variable publishes as a required blank, so each role is its own image with the choice baked in.
# upstream: valkey-io/valkey
ARG BASE
FROM ${BASE}
ARG CONF
ENV OA_VALKEY_CONF=/usr/local/etc/valkey/${CONF}.conf
