# otel_redis

OpenTelemetry instrumentation for package:redis. Wraps Redis commands in CLIENT-kind spans following OTel stable semantic conventions (db.system.name=redis, db.operation.name, server.address).

Span names follow OTel stable semantic conventions:
`{operation.name} {target}` with no system prefix (the system is
already in `db.system.name` / `messaging.system`).

Part of the [Dartastic](https://dartastic.io) OpenTelemetry family.
