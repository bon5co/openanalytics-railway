# Open Analytics on Railway

Thin wrapper images that let the [Open Analytics](https://github.com/OpenLabs-so/openanalytics) v0.8.0
stack run as a Railway template. Each image is `FROM` the upstream image pinned by digest, plus an
entrypoint that waits for its peers, derives the signing keys from per-purpose seeds, bootstraps the
first admin account, and puts nginx in front of the public node services so the client IP is the first
`X-Forwarded-For` hop.

Images: `ghcr.io/bon5co/openanalytics-railway-{api,gateway,collector,realtime,worker,migrate,web,clickhouse,valkey-queue,valkey-realtime}`.

Open Analytics is AGPL-3.0; this wrapper changes no upstream source.
