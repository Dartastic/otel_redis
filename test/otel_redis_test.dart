// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.
//
// These tests exercise the span/attribute machinery of
// `tracedRedisCall` using a fake `invoke` callback — no real Redis
// server is needed.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_redis/otel_redis.dart';
import 'package:test/test.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;
  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

Map<String, Object> _attrMap(Span span) => {
      for (final a in span.attributes.toList()) a.key: a.value,
    };

void main() {
  group('tracedRedisCall', () {
    late _MemorySpanExporter exporter;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'otel_redis-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
    });

    tearDown(() async {
      await OTel.shutdown();
      await OTel.reset();
    });

    test('GET names span "GET <key>" per OTel stable semconv', () async {
      await tracedRedisCall<String?>(
        command: ['GET', 'user:42'],
        invoke: () async => 'alice',
      );
      expect(exporter.spans, hasLength(1));
      final span = exporter.spans.single;
      // Stable semconv: span name is `{op} {target}` — no system prefix.
      expect(span.name, 'GET user:42');
      final attrs = _attrMap(span);
      expect(attrs['db.system.name'], 'redis');
      expect(attrs['db.operation.name'], 'GET');
      expect(attrs['db.collection.name'], 'user:42');
    });

    test('SET uppercases operation and extracts key', () async {
      await tracedRedisCall<String?>(
        command: ['set', 'session:abc', 'token'],
        invoke: () async => 'OK',
      );
      final span = exporter.spans.single;
      expect(span.name, 'SET session:abc');
      expect(_attrMap(span)['db.operation.name'], 'SET');
    });

    test('span name drops key when command has no second argument', () async {
      await tracedRedisCall<String>(
        command: ['PING'],
        invoke: () async => 'PONG',
      );
      // No key applies — span name is just the operation, with NO
      // trailing system or namespace.
      expect(exporter.spans.single.name, 'PING');
    });

    test('namespace + server attrs recorded', () async {
      await tracedRedisCall<int>(
        command: ['INCR', 'counter'],
        namespace: '0',
        serverAddress: 'redis.internal',
        serverPort: 6379,
        invoke: () async => 1,
      );
      final attrs = _attrMap(exporter.spans.single);
      expect(attrs['db.namespace'], '0');
      expect(attrs['server.address'], 'redis.internal');
      expect(attrs['server.port'], 6379);
    });

    test('records exception and sets error status on throw', () async {
      await expectLater(
        tracedRedisCall<String>(
          command: ['GET', 'missing'],
          invoke: () async => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      final span = exporter.spans.single;
      expect(span.status, SpanStatusCode.Error);
      expect(_attrMap(span)['error.type'], 'StateError');
    });

    test('zone-scoped suppression skips span creation', () async {
      await runWithoutRedisInstrumentationAsync(() async {
        await tracedRedisCall<String>(
          command: ['GET', 'x'],
          invoke: () async => '',
        );
      });
      expect(exporter.spans, isEmpty);
    });

    test('string command still extracts operation', () async {
      await tracedRedisCall<String>(
        command: 'CLUSTER NODES',
        invoke: () async => '',
      );
      final attrs = _attrMap(exporter.spans.single);
      expect(attrs['db.operation.name'], 'CLUSTER');
    });
  });
}
