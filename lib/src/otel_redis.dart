// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:redis/redis.dart' as r;

import 'otel_redis_suppression.dart';

const _tracerName = 'otel_redis';
const _dbSystem = 'redis';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Uppercases the first element of a Redis command array.
///
/// `['SET', 'key', 'value']` -> `SET`
/// `['hget', 'h', 'f']`      -> `HGET`
String? _extractOperation(Object? cmd) {
  if (cmd is List && cmd.isNotEmpty) {
    final first = cmd.first;
    if (first is String) return first.toUpperCase();
  } else if (cmd is String) {
    final trimmed = cmd.trimLeft();
    final m = RegExp(r'^([A-Za-z_]+)').firstMatch(trimmed);
    return m?.group(1)?.toUpperCase();
  }
  return null;
}

/// Pulls the key argument from a Redis command list — the second element.
///
/// Returns `null` for commands without a key (PING, INFO, FLUSHDB, etc.)
/// or when the second element is not a string.
String? _extractKey(Object? cmd) {
  if (cmd is List && cmd.length >= 2) {
    final second = cmd[1];
    if (second is String) return second;
  }
  return null;
}

/// Builds the OTel attributes for a Redis command span following
/// the stable database semantic conventions.
Attributes _attrs({
  required String? operation,
  String? key,
  String? namespace,
  String? serverAddress,
  int? serverPort,
}) =>
    OTel.attributesFromMap(<String, Object>{
      Database.dbSystem.key: _dbSystem,
      Database.dbSystemName.key: _dbSystem,
      if (operation != null) Database.dbOperation.key: operation,
      if (operation != null) Database.dbOperationName.key: operation,
      if (key != null) Database.dbCollectionName.key: key,
      if (namespace != null) Database.dbNamespace.key: namespace,
      if (serverAddress != null)
        ServerResource.serverAddress.key: serverAddress,
      if (serverPort != null) ServerResource.serverPort.key: serverPort,
    });

/// Runs [invoke] inside a CLIENT-kind span named `<OP> <key>` (or just
/// `<OP>` when no key applies), with `db.system.name=redis` and the
/// standard OTel db attributes.
///
/// Pass [command] as the same list/string you would pass to
/// `Command.send_object` so the operation and key can be extracted
/// automatically. Pass [operationOverride] / [keyOverride] when you
/// already know them.
///
/// [namespace] becomes `db.namespace` (Redis DB index, e.g. `"0"`).
/// [serverAddress] / [serverPort] become `server.address` / `server.port`.
///
/// Exceptions are recorded with `error.type` + `recordException`, the
/// span status is set to `Error`, and the exception is rethrown.
Future<R> tracedRedisCall<R>({
  required Object? command,
  required Future<R> Function() invoke,
  String? operationOverride,
  String? keyOverride,
  String? namespace,
  String? serverAddress,
  int? serverPort,
}) async {
  if (redisInstrumentationSuppressed()) return invoke();
  final op = operationOverride ?? _extractOperation(command);
  final key = keyOverride ?? _extractKey(command);
  // OTel stable semconv: span name is `{operation} {target}` with NO
  // system prefix. `db.system.name=redis` already carries the system.
  final spanName = key != null ? '${op ?? "COMMAND"} $key' : op ?? 'COMMAND';
  final span = _tracer().startSpan(
    spanName,
    kind: SpanKind.client,
    attributes: _attrs(
      operation: op,
      key: key,
      namespace: namespace,
      serverAddress: serverAddress,
      serverPort: serverPort,
    ),
  );
  try {
    return await invoke();
  } catch (e, st) {
    span.addAttributes(
      OTel.attributes([
        OTel.attributeString(
          ErrorResource.errorType.key,
          e.runtimeType.toString(),
        ),
      ]),
    );
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Traced versions of the common `Command` send paths.
extension OTelCommand on r.Command {
  /// Traced `send_object`. The command argument is best-effort parsed
  /// for the Redis operation (first element, uppercased) and key
  /// (second element when present).
  ///
  /// Pass [namespace] when you know the Redis DB index (becomes
  /// `db.namespace`). Pass [serverAddress] / [serverPort] when known.
  Future<dynamic> sendObjectTraced(
    Object obj, {
    String? operationOverride,
    String? keyOverride,
    String? namespace,
    String? serverAddress,
    int? serverPort,
  }) {
    return tracedRedisCall<dynamic>(
      command: obj,
      operationOverride: operationOverride,
      keyOverride: keyOverride,
      namespace: namespace,
      serverAddress: serverAddress,
      serverPort: serverPort,
      invoke: () => send_object(obj),
    );
  }
}
