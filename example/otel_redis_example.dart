// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.
//
// Demonstrates otel_redis against a local Redis server.
// Run a server first, e.g.:
//   docker run --rm -p 6379:6379 redis:7

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_redis/otel_redis.dart';
import 'package:redis/redis.dart';

Future<void> main() async {
  // Spans export via OTLP (default http://localhost:4318).
  await OTel.initialize(serviceName: 'otel_redis-example');

  final conn = RedisConnection();
  final command = await conn.connect('localhost', 6379);

  // Drop-in traced replacement for `send_object`. Emits a CLIENT span
  // named `SET greeting` with db.system.name=redis,
  // db.operation.name=SET, db.collection.name=greeting.
  await command.sendObjectTraced(
    ['SET', 'greeting', 'hello'],
    serverAddress: 'localhost',
    serverPort: 6379,
  );

  final value = await command.sendObjectTraced(
    ['GET', 'greeting'],
    serverAddress: 'localhost',
    serverPort: 6379,
  );
  print('GET greeting -> $value');

  // Manual span around any block of Redis work.
  final pong = await tracedRedisCall<Object?>(
    command: ['PING'],
    serverAddress: 'localhost',
    serverPort: 6379,
    invoke: () => command.send_object(['PING']),
  );
  print('tracedRedisCall -> $pong');

  // Zone-scoped suppression: no spans inside this block.
  await runWithoutRedisInstrumentationAsync(() async {
    await command.sendObjectTraced(['GET', 'greeting']); // not traced
  });

  await conn.close();
  await OTel.shutdown();
}
