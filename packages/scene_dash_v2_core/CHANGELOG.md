# Changelog

## 0.5.2
- Cache parked-component scans until new parts arrive; explicit component
  registration claims waiting parts, and despawn/reset release unclaimed parts.
- Use weak identity tracking for disposed resources. Shutdown attempts all
  cleanup callbacks and resources, then reports a `CleanupException` containing
  the original exceptions and stack traces.
- Make `consumeAny` use a constant-time cursor advance without a result list.
- Add `EventReader.dispose()` and release system readers on shutdown.
- Add `snapshot()` to query views; `.records` remains an eager allocating alias.
- Resolve function-based system ordering at boot, allowing references to later
  features. Validate missing and cross-schedule references, including
  `independentOf` when conflict detection is disabled.
- Check local documentation links and compile runnable Markdown examples in CI.

## 0.5.1
- a variety of ordering fixes for events and command buffers

## 0.5.0
- upgrade deps

## 0.4.0
- upgrade deps

## 0.2.0
- adds new routine mechanism for better organizing sequenced game logic

## 0.1.3
- adds custom schedules feature

## 0.1.2

- minor fixes for pub dev

## 0.1.0

First release.
