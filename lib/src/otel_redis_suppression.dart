// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

const _key = #dartastic_otel_redis_suppress;

/// Whether Redis instrumentation is suppressed in the current [Zone].
bool redisInstrumentationSuppressed() => Zone.current[_key] == true;

/// Runs [body] with Redis instrumentation suppressed — traced calls
/// inside it execute normally but emit no spans.
T runWithoutRedisInstrumentation<T>(T Function() body) =>
    runZoned(body, zoneValues: {_key: true});

/// Async variant of [runWithoutRedisInstrumentation].
Future<T> runWithoutRedisInstrumentationAsync<T>(
  Future<T> Function() body,
) =>
    runZoned(body, zoneValues: {_key: true});
