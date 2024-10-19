# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v2.6.4](https://github.com/cabol/nebulex/tree/v2.6.4) (2024-10-19)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.6.3...v2.6.4)

**Closed issues:**

- [Proposal] A New GC Strategy for Local Generation
  [#184](https://github.com/cabol/nebulex/issues/184)

**Merged pull requests:**

- Fix race condition in multilevel cache replication
  [#232](https://github.com/cabol/nebulex/pull/232)
  ([costaraphael](https://github.com/costaraphael))
- Fix typos again
  [#230](https://github.com/cabol/nebulex/pull/230)
  ([kianmeng](https://github.com/kianmeng))

## [v2.6.3](https://github.com/cabol/nebulex/tree/v2.6.3) (2024-08-05)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.6.2...v2.6.3)

**Closed issues:**

- `Cache.all(nil, return: :value)` with a partitioned cache gives incorrect
  results
  [#228](https://github.com/cabol/nebulex/issues/228)
- 2.6.2 is missing from tags and releases on github
  [#227](https://github.com/cabol/nebulex/issues/227)

**Merged pull requests:**

- `Cache.all(nil, return: :value)` did not correctly handle values that are
  lists.
  [#229](https://github.com/cabol/nebulex/pull/229)
  ([jweinkam](https://github.com/jweinkam))

## [v2.6.2](https://github.com/cabol/nebulex/tree/v2.6.2) (2024-06-15)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.6.1...v2.6.2)

**Closed issues:**

- Having a cache per user ID
  [#224](https://github.com/cabol/nebulex/issues/224)

**Merged pull requests:**

- Fix some compiler warnings in Elixir 1.17
  [#222](https://github.com/cabol/nebulex/pull/222)
  ([peaceful-james](https://github.com/peaceful-james))

## [v2.6.1](https://github.com/cabol/nebulex/tree/v2.6.1) (2024-02-24)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.6.0...v2.6.1)

**Merged pull requests:**

- Improve variable handing in key generators
  [#221](https://github.com/cabol/nebulex/pull/221)
  ([hissssst](https://github.com/hissssst))

## [v2.6.0](https://github.com/cabol/nebulex/tree/v2.6.0) (2024-01-21)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.5.2...v2.6.0)

**Fixed bugs:**

- Fix compatibility with Elixir 1.15 and 1.16
  [#220](https://github.com/cabol/nebulex/issues/220)

**Closed issues:**

- `Multilevel` inclusive cache doesn't duplicate entries backwards on
  `get_all/2`
  [#219](https://github.com/cabol/nebulex/issues/219)
- Empty arguments list passed to `generate/3` in Elixir 1.16
  [#218](https://github.com/cabol/nebulex/issues/218)
- Regression on decorated functions and Elixir 1.16
  [#216](https://github.com/cabol/nebulex/issues/216)
- Bug on Local adapter when using `delete_all` and keys are nested tuples:
  not a valid match specification
  [#211](https://github.com/cabol/nebulex/issues/211)
- `Nebulex.RegistryLookupError`
  [#207](https://github.com/cabol/nebulex/issues/207)
- Docs on Migrating to v2 from Nebulex.Adapters.Dist.Cluster
  [#198](https://github.com/cabol/nebulex/issues/198)

**Merged pull requests:**

- Partitioned Adapter supports two-item tuples as keys
  [#214](https://github.com/cabol/nebulex/pull/214)
  ([twinn](https://github.com/twinn))
- Adds nebulex Ecto adapter
  [#212](https://github.com/cabol/nebulex/pull/212)
  ([hissssst](https://github.com/hissssst))

## [v2.5.2](https://github.com/cabol/nebulex/tree/v2.5.2) (2023-07-14)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.5.1...v2.5.2)

**Closed issues:**

- Replicated adapter syncing during rolling deployment.
  [#209](https://github.com/cabol/nebulex/issues/209)
- Ambiguity regarding ttl and `gc_interval` relation.
  [#208](https://github.com/cabol/nebulex/issues/208)
- Seeing Nebulex.RPCError during deployments with partitioned adapter.
  [#206](https://github.com/cabol/nebulex/issues/206)
- Random `:erpc`, `:timeout` with partitioned get.
  [#202](https://github.com/cabol/nebulex/issues/202)
- Processes reading from cache blocked by generational gc process.
  [#197](https://github.com/cabol/nebulex/issues/197)

**Merged pull requests:**

- Delay flushing ets table to avoid blocking processes using it.
  [#210](https://github.com/cabol/nebulex/pull/210)
  ([szajbus](https://github.com/szajbus))

## [v2.5.1](https://github.com/cabol/nebulex/tree/v2.5.1) (2023-05-27)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.5.0...v2.5.1)

**Merged pull requests:**

- Fix `nil` check in `Nebulex.Adapters.Multilevel.get/3`
  [#205](https://github.com/cabol/nebulex/pull/205)
  ([1100x1100](https://github.com/1100x1100))
- `mix nbx.gen.cache` example fixed
  [#204](https://github.com/cabol/nebulex/pull/204)
  ([hissssst](https://github.com/hissssst))

## [v2.5.0](https://github.com/cabol/nebulex/tree/v2.5.0) (2023-05-13)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.4.2...v2.5.0)

**Implemented enhancements:**

- Support for functions that can set TTL in Decorator similar to Match
  [#200](https://github.com/cabol/nebulex/issues/200)
- Improve default match function in decorators to cover more scenarios
  [#177](https://github.com/cabol/nebulex/issues/177)
- Adapters implementation guide
  [#96](https://github.com/cabol/nebulex/issues/96)

**Fixed bugs:**

- Issue with keys set to `false` when calling `get_all` in local adapter
  [#187](https://github.com/cabol/nebulex/issues/187)

**Closed issues:**

- Is there any way to get the size of the cache?
  [#203](https://github.com/cabol/nebulex/issues/203)
- Where to use load/2, dump/2
  [#201](https://github.com/cabol/nebulex/issues/201)
- `Nebulex.Cache` callbacks mention "Shared Options" section that do not exist
  [#199](https://github.com/cabol/nebulex/issues/199)
- Errors when storing nil values
  [#195](https://github.com/cabol/nebulex/issues/195)
- Unregistering cache in registry happens after cache shuts down
  [#194](https://github.com/cabol/nebulex/issues/194)
- Is there a good way to evict multiple caches at once by some conditions?
  [#192](https://github.com/cabol/nebulex/issues/192)
- Unable to use module attributes when specifying a MFA cache within the decorator
  [#191](https://github.com/cabol/nebulex/issues/191)
- Nebulex crash when `gc_interval` is not set
  [#182](https://github.com/cabol/nebulex/issues/182)
- `ArgumentError` * 1st argument: the table identifier does not refer to an existing ETS table
  [#181](https://github.com/cabol/nebulex/issues/181)
- Feedback for `NebulexLocalDistributedAdapter`
  [#180](https://github.com/cabol/nebulex/issues/180)
- Multilevel invalidation
  [#179](https://github.com/cabol/nebulex/issues/179)
- External cache-key references on `cacheable` decorator
  [#178](https://github.com/cabol/nebulex/issues/178)
- [multiple clause functions] Cannot use ignored variables in decorator keys
  [#173](https://github.com/cabol/nebulex/issues/173)
- Ability for referencing a key in the `cacheable` decorator via `:references` option
  [#169](https://github.com/cabol/nebulex/issues/169)
- Multi level caching suggestion?
  [#168](https://github.com/cabol/nebulex/issues/168)

**Merged pull requests:**

- Fix `Local.get_all` with false values
  [#186](https://github.com/cabol/nebulex/pull/186)
  ([renatoaguiar](https://github.com/renatoaguiar))
- Add NebulexLocalMultilevelAdapter to the list
  [#185](https://github.com/cabol/nebulex/pull/185)
  ([martosaur](https://github.com/martosaur))
- Fix the crash when `gc_interval` is not set
  [#183](https://github.com/cabol/nebulex/pull/183)
  ([dongfuye](https://github.com/dongfuye))
- [#169] Reference a key in `cacheable` decorator via `:references` option
  [#176](https://github.com/cabol/nebulex/pull/176)
  ([cabol](https://github.com/cabol))
- Creating New Adapter guide
  [#175](https://github.com/cabol/nebulex/pull/175)
  ([martosaur](https://github.com/martosaur))

## [v2.4.2](https://github.com/cabol/nebulex/tree/v2.4.2) (2022-11-04)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.4.1...v2.4.2)

**Closed issues:**

- Adapter configuration per-env?
  [#171](https://github.com/cabol/nebulex/issues/171)
- On-change handler for write-through decorators
  [#165](https://github.com/cabol/nebulex/issues/165)
- Document test env setup with decorators?
  [#155](https://github.com/cabol/nebulex/issues/155)
- Managing Failovers in the cluster
  [#131](https://github.com/cabol/nebulex/issues/131)

**Merged pull requests:**

- Make Multilevel adapter apply deletes in reverse order
  [#174](https://github.com/cabol/nebulex/pull/174)
  ([martosaur](https://github.com/martosaur))
- Use import Bitwise instead of use Bitwise
  [#172](https://github.com/cabol/nebulex/pull/172)
  ([ryvasquez](https://github.com/ryvasquez))
- Fix result of getting value by non existent key
  [#166](https://github.com/cabol/nebulex/pull/166)
  ([fuelen](https://github.com/fuelen))

## [v2.4.1](https://github.com/cabol/nebulex/tree/v2.4.1) (2022-07-10)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.4.0...v2.4.1)

**Closed issues:**

- Telemetry handler fails when using `put_all`
  [#163](https://github.com/cabol/nebulex/issues/163)
- Fix `incr/3` to initialize default value if ttl is expired
  [#162](https://github.com/cabol/nebulex/issues/162)
- Cannot use variables in decorator keys
  [#161](https://github.com/cabol/nebulex/issues/161)

**Merged pull requests:**

- Update stats handler to handle map type argument passed to `put_all`
  [#164](https://github.com/cabol/nebulex/pull/164)
  ([ananthakumaran](https://github.com/ananthakumaran))
- New adapter with Horde
  [#160](https://github.com/cabol/nebulex/pull/160)
  ([eliasdarruda](https://github.com/eliasdarruda))

## [v2.4.0](https://github.com/cabol/nebulex/tree/v2.4.0) (2022-06-05)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.3.2...v2.4.0)

**Closed issues:**

- Multiple keys deletion at once with predefined query `{:in, keys}`
  [#159](https://github.com/cabol/nebulex/issues/159)
- Duplicate data keys when put in replicated cache when start app
  [#158](https://github.com/cabol/nebulex/issues/158)
- Option `:cache` admits MFA tuple `{module, function, args}` as value on the
  annotated functions
  [#157](https://github.com/cabol/nebulex/issues/157)

**Merged pull requests:**

- Allow passing dynamic cache configuration to the decorators
  [#156](https://github.com/cabol/nebulex/pull/156)
  ([suzdalnitski](https://github.com/suzdalnitski))
- Fix typo
  [#154](https://github.com/cabol/nebulex/pull/154)
  ([kianmeng](https://github.com/kianmeng))
- User erlef/setup-beam for GitHub Actions
  [#153](https://github.com/cabol/nebulex/pull/153)
  ([kianmeng](https://github.com/kianmeng))
- Fix typos
  [#152](https://github.com/cabol/nebulex/pull/152)
  ([george124816](https://github.com/george124816))
- Fix config comments
  [#150](https://github.com/cabol/nebulex/pull/150)
  ([alexandrubagu](https://github.com/alexandrubagu))

## [v2.3.2](https://github.com/cabol/nebulex/tree/v2.3.2) (2022-03-29)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.3.1...v2.3.2)

**Closed issues:**

- Transaction in Replicate not block global
  [#147](https://github.com/cabol/nebulex/issues/147)
- The match spec in the doc should be of size 5 instead of size 4
  [#146](https://github.com/cabol/nebulex/issues/146)
- Performance penalty when using Multilevel + Local + Redis adapters
  [#138](https://github.com/cabol/nebulex/issues/138)

## [v2.3.1](https://github.com/cabol/nebulex/tree/v2.3.1) (2022-03-13)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.3.0...v2.3.1)

**Implemented enhancements:**

- Improve cache memory/size checks for local adapter
  [#145](https://github.com/cabol/nebulex/issues/145)

**Closed issues:**

- What happens if cache uses more memory than the machine have?
  [#144](https://github.com/cabol/nebulex/issues/144)

## [v2.3.0](https://github.com/cabol/nebulex/tree/v2.3.0) (2021-11-13)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.2.1...v2.3.0)

**Implemented enhancements:**

- Additional Telemetry events for the partitioned adapter
  [#143](https://github.com/cabol/nebulex/issues/143)
- Add option `:join_timeout` to the partitioned adapter
  [#142](https://github.com/cabol/nebulex/issues/142)
- Option `:on_error` for caching annotations to ignore cache exceptions when
  required [#141](https://github.com/cabol/nebulex/issues/141)
- Fix `Nebulex.Adapters.Multilevel.get_all/3` to call the same invoked function
  into the underlying levels [#139](https://github.com/cabol/nebulex/issues/139)
- Option `:key_generator` admits MFA tuple `{module, function, args}` as value
  on the annotated functions [#135](https://github.com/cabol/nebulex/issues/135)

**Closed issues:**

- Unhandled :erpc failures
  [#140](https://github.com/cabol/nebulex/issues/140)
- Release a version with new telemetry dependency
  [#137](https://github.com/cabol/nebulex/issues/137)
- handle\_rpc\_multi\_call/3 doesn't handle empty list in res argument
  [#136](https://github.com/cabol/nebulex/issues/136)
- New telemetry isn't user friendly
  [#129](https://github.com/cabol/nebulex/issues/129)

## [v2.2.1](https://github.com/cabol/nebulex/tree/v2.2.1) (2021-10-18)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.2.0...v2.2.1)

**Closed issues:**

- Compilation error if cacheable decorator has an argument ignored
  (FIX: Skip ignored and/or unassigned arguments when invoking key generator)
  [#134](https://github.com/cabol/nebulex/issues/134)
- Is it possible to use return value in key-generation along with the passed parameters?
  [#132](https://github.com/cabol/nebulex/issues/132)

**Merged pull requests:**

- Fix `max_size` to be actually 1 million instead of 100,000
  [#133](https://github.com/cabol/nebulex/pull/133)
  ([adamz-prescribefit](https://github.com/adamz-prescribefit))

## [v2.2.0](https://github.com/cabol/nebulex/tree/v2.2.0) (2021-09-10)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.1.1...v2.2.0)

**Implemented enhancements:**

- Improve the Telemetry documentation for the partitioned, replicated,
  and multi-level adapters. [#130](https://github.com/cabol/nebulex/issues/130)
- Make `:keys` option available for `cache_put` annotation
  [#128](https://github.com/cabol/nebulex/issues/128)

**Closed issues:**

- `cache_put` does not work when passing a list of keys
  [#127](https://github.com/cabol/nebulex/issues/127)

## [v2.1.1](https://github.com/cabol/nebulex/tree/v2.1.1) (2021-06-25)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.1.0...v2.1.1)

**Implemented enhancements:**

- Add cache option `:default_key_generator` to change the key generator at
  compile-time [#126](https://github.com/cabol/nebulex/issues/126)

**Closed issues:**

- Hits/Misses statistics not updated when using `get_all`
  [#125](https://github.com/cabol/nebulex/issues/125)
- Compilation fails in file lib/nebulex/rpc.ex
  [#123](https://github.com/cabol/nebulex/issues/123)
- Nebulex.Caching.SimpleKeyGenerator should produce a unique key
  [#122](https://github.com/cabol/nebulex/issues/122)

**Merged pull requests:**

- Fix typo in `getting-started.md` guide
  [#124](https://github.com/cabol/nebulex/pull/124)
  ([RudolfMan](https://github.com/RudolfMan))

## [v2.1.0](https://github.com/cabol/nebulex/tree/v2.1.0) (2021-05-15)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.0.0...v2.1.0)

**Added features:**

- Telemetry handler for aggregating and/or handling cache stats
  [#119](https://github.com/cabol/nebulex/issues/119)
- Instrument multi-level adapter with the recommended Telemetry events
  [#118](https://github.com/cabol/nebulex/issues/118)
- Instrument replicated adapter with the recommended Telemetry events
  [#117](https://github.com/cabol/nebulex/issues/117)
- Instrument partitioned adapter with the recommended Telemetry events
  [#116](https://github.com/cabol/nebulex/issues/116)
- Instrument the local adapter with the recommended Telemetry events
  [#115](https://github.com/cabol/nebulex/issues/115)
- Add custom key generator support by implementing
  `Nebulex.Caching.KeyGenerator` behaviour
  [#109](https://github.com/cabol/nebulex/issues/109)
- Add default key generator `Nebulex.Caching.SimpleKeyGenerator`

**Implemented enhancements:**

- Settle down the foundations to support Telemetry events in the adapters
  [#114](https://github.com/cabol/nebulex/issues/114)
- Support `:before_invocation` option in the `cache_evict` annotation
  [#110](https://github.com/cabol/nebulex/issues/110)

**Fixed bugs:**

- Possible race-condition when removing older generation while ongoing
  operations on it [#121](https://github.com/cabol/nebulex/issues/121)
- Bug on boolean values [#111](https://github.com/cabol/nebulex/issues/111)
- Issue when raising Nebulex.RPCMultiCallError in replicated adapter
  [#108](https://github.com/cabol/nebulex/issues/108)

**Closed issues:**

- Use of `:ets` reference after delete
  [#120](https://github.com/cabol/nebulex/issues/120)
- Node's that are gracefully shutting down trigger Nebulex errors
  [#113](https://github.com/cabol/nebulex/issues/113)
- Rolling deployment after adding the cache does not start new nodes
  [#107](https://github.com/cabol/nebulex/issues/107)
- Unable to migrate to v.2 https://hexdocs.pm/nebulex/migrating-to-v2.html is
  broken [#102](https://github.com/cabol/nebulex/issues/102)

**Merged pull requests:**

- Avoid calling `cacheable()` method when cached value is `false`
  [#112](https://github.com/cabol/nebulex/pull/112)
  ([escobera](https://github.com/escobera))
- Declarative annotation-based caching improvements
  [#105](https://github.com/cabol/nebulex/pull/105)
  ([cabol](https://github.com/cabol))

## [v2.0.0](https://github.com/cabol/nebulex/tree/v2.0.0) (2021-02-20)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.0.0-rc.2...v2.0.0)

**Added features:**

- Added `delete_all/2` and `count_all/2` functions to the Cache API
  [#100](https://github.com/cabol/nebulex/issues/100)
- Added `decr/3` to the Cache API.

**Implemented enhancements:**

- Added `join_cluster` and `leave_cluster` functions to the distributed adapters
  [#104](https://github.com/cabol/nebulex/issues/104)
- Removed `Nebulex.Time.expiry_tine/2`; use `:timer.(seconds|minutes|hours)/1`
  instead.

**Closed issues:**

- Migrating to v2 link is broken
  [#103](https://github.com/cabol/nebulex/issues/103)
- Fixed replicated adapter to work properly with dynamic caches
  [#101](https://github.com/cabol/nebulex/issues/101)

## [v2.0.0-rc.2](https://github.com/cabol/nebulex/tree/v2.0.0-rc.2) (2021-01-06)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.0.0-rc.1...v2.0.0-rc.2)

**Added features:**

- Added adapter `Nebulex.Adapters.Nil` for disabling caching
  [#88](https://github.com/cabol/nebulex/issues/88)
- Added adapter for `whitfin/cachex`
  [#20](https://github.com/cabol/nebulex/issues/20)

**Implemented enhancements:**

- Improved replicated adapter to ensure better consistency across the nodes
  [#99](https://github.com/cabol/nebulex/issues/99)
- Refactored Nebulex task for generating caches
  [#97](https://github.com/cabol/nebulex/issues/97)
- Added `Nebulex.Adapter.Stats` behaviour as optional
  [#95](https://github.com/cabol/nebulex/issues/95)
- Added `Nebulex.Adapter.Entry` and `Nebulex.Adapter.Storage` behaviours
  [#93](https://github.com/cabol/nebulex/issues/93)
- Added `:default` option to the `incr/3` callback
  [#92](https://github.com/cabol/nebulex/issues/92)
- Fixed `Nebulex.RPC` to use `:erpc` when depending on OTP 23 or higher,
  otherwise use current implementation
  [#91](https://github.com/cabol/nebulex/issues/91)

**Fixed bugs:**

- Fixed stats to update evictions when a new generation is created and the
  older is deleted [#98](https://github.com/cabol/nebulex/issues/98)

**Closed issues:**

- Is there a way to disable caching entirely?
  [#87](https://github.com/cabol/nebulex/issues/87)
- Slow cache under moderate simultaneous load
  [#80](https://github.com/cabol/nebulex/issues/80)
- `mix nebulex.gen.cache` replaces everything in folder
  [#75](https://github.com/cabol/nebulex/issues/75)
- Replicated hash_slots for partitioned adapter
  [#65](https://github.com/cabol/nebulex/issues/65)

**Merged pull requests:**

- Overall fixes and enhancements for adapter behaviours
  [#94](https://github.com/cabol/nebulex/pull/94)
  ([cabol](https://github.com/cabol))
- Typo in code example 👀
  [#89](https://github.com/cabol/nebulex/pull/89)
  ([Awlexus](https://github.com/Awlexus))

## [v2.0.0-rc.1](https://github.com/cabol/nebulex/tree/v2.0.0-rc.1) (2020-11-15)

[Full Changelog](https://github.com/cabol/nebulex/compare/v2.0.0-rc.0...v2.0.0-rc.1)

**Implemented enhancements:**

- Made the local adapter completely agnostic to the cache name
- Added documentation in local adapter for eviction settings, caveats and
  recommendations.
- Added support for new `:pg` module since OTP 23
  [#84](https://github.com/cabol/nebulex/issues/84)

**Closed issues:**

- Error on `cache.import` using ReplicatedCache [#86](https://github.com/cabol/nebulex/issues/86)
- `{:EXIT, #PID<0.2945.0>, :normal}` [#79](https://github.com/cabol/nebulex/issues/79)
- `opts[:stats]` not getting through to the adapter [#78](https://github.com/cabol/nebulex/issues/78)
- Partitioned Cache + stats + multiple nodes causes failure [#77](https://github.com/cabol/nebulex/issues/77)
- Recommended gc settings? [#76](https://github.com/cabol/nebulex/issues/76)

**Merged pull requests:**

- Add test for unflushed messages with exits trapped [#85](https://github.com/cabol/nebulex/pull/85)
  ([garthk](https://github.com/garthk))
- Misc doc changes [#83](https://github.com/cabol/nebulex/pull/83)
  ([kianmeng](https://github.com/kianmeng))
- Use TIDs for the generation tables instead of names [#82](https://github.com/cabol/nebulex/pull/82)
  ([cabol](https://github.com/cabol))
- Update `:shards` dependency to the latest version [#81](https://github.com/cabol/nebulex/pull/81)
  ([cabol](https://github.com/cabol))

## [v2.0.0-rc.0](https://github.com/cabol/nebulex/tree/v2.0.0-rc.0) (2020-07-05)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.2.2...v2.0.0-rc.0)

**Closed issues:**

- Asynchronous testing struggles [#72](https://github.com/cabol/nebulex/issues/72)
- `MyCache.ttl/0` is undefined or private [#71](https://github.com/cabol/nebulex/issues/71)
- Add telemetry integration [#62](https://github.com/cabol/nebulex/issues/62)

**Merged pull requests:**

- Crafting Nebulex v2 [#68](https://github.com/cabol/nebulex/pull/68)
  ([cabol](https://github.com/cabol))

## [v1.2.2](https://github.com/cabol/nebulex/tree/v1.2.2) (2020-06-11)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.2.1...v1.2.2)

**Closed issues:**

- Fix: Dialyzer [#74](https://github.com/cabol/nebulex/issues/74)
- Question: Use environment variables for config [#70](https://github.com/cabol/nebulex/issues/70)

**Merged pull requests:**

- Fix: Dialyzer useless control flow [#73](https://github.com/cabol/nebulex/pull/73)
  ([filipeherculano](https://github.com/filipeherculano))

## [v1.2.1](https://github.com/cabol/nebulex/tree/v1.2.1) (2020-04-12)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.2.0...v1.2.1)

**Fixed bugs:**

- Fix issue when memory check is ran for the generation manager
  [#69](https://github.com/cabol/nebulex/issues/69)

## [v1.2.0](https://github.com/cabol/nebulex/tree/v1.2.0) (2020-03-30)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.1.1...v1.2.0)

**Implemented enhancements:**

- Refactor `Nebulex.Caching` in order to use annotated functions via decorators
  [#66](https://github.com/cabol/nebulex/issues/66)

**Fixed bugs:**

- Sporadic `:badarg` error [#52](https://github.com/cabol/nebulex/issues/52)

**Closed issues:**

- Question: disabling cache conditionally in defcacheable [#63](https://github.com/cabol/nebulex/issues/63)
- Support for persistence operations [#61](https://github.com/cabol/nebulex/issues/61)
- Implement adapter for replicated topology [#60](https://github.com/cabol/nebulex/issues/60)

**Merged pull requests:**

- [#66] Refactor `Nebulex.Caching` to use annotated functions via decorators
  [#67](https://github.com/cabol/nebulex/pull/67) ([cabol](https://github.com/cabol))
- Fixes and enhancements for `v1.2.0` [#64](https://github.com/cabol/nebulex/pull/64)
  ([cabol](https://github.com/cabol))
- Features for next release (`v1.2.0`) [#59](https://github.com/cabol/nebulex/pull/59)
  ([cabol](https://github.com/cabol))

## [v1.1.1](https://github.com/cabol/nebulex/tree/v1.1.1) (2019-11-11)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.1.0...v1.1.1)

**Implemented enhancements:**

- Add capability to limit cache size  [#53](https://github.com/cabol/nebulex/issues/53)
- Ability to "get or set" a key [#49](https://github.com/cabol/nebulex/issues/49)
- Multilevel Cache: transaction/3 is attempting to change all levels multiple times.
  [#35](https://github.com/cabol/nebulex/issues/35)

**Closed issues:**

- Pre Expire Hook [#57](https://github.com/cabol/nebulex/issues/57)
- Add matching option on returned result to Nebulex.Caching [#55](https://github.com/cabol/nebulex/issues/55)
- Multi Level with dist not working as expected [#54](https://github.com/cabol/nebulex/issues/54)
- Adapter for FoundationDB [#51](https://github.com/cabol/nebulex/issues/51)

**Merged pull requests:**

- Add match option to Nebulex.Caching [#56](https://github.com/cabol/nebulex/pull/56)
  ([polmiro](https://github.com/polmiro))

## [v1.1.0](https://github.com/cabol/nebulex/tree/v1.1.0) (2019-05-11)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.1...v1.1.0)

**Implemented enhancements:**

- Refactor flush action in the local adapter to delete all objects instead of
  deleting all generation tables [#48](https://github.com/cabol/nebulex/issues/48)
- Write a guide for `Nebulex.Caching` [#45](https://github.com/cabol/nebulex/issues/45)
- Turn `Nebulex.Adapter.NodeSelector` into a generic hash behavior `Nebulex.Adapter.Hash`
  [#44](https://github.com/cabol/nebulex/issues/44)
- Turn `Nebulex.Adapters.Dist.RPC` into a reusable utility [#43](https://github.com/cabol/nebulex/issues/43)
- Add support to evict multiple keys from cache in `defevict`  [#42](https://github.com/cabol/nebulex/issues/42)

**Fixed bugs:**

- custom ttl on mulltilevel cache gets overwritten [#46](https://github.com/cabol/nebulex/issues/46)

**Closed issues:**

- Will nebulex support replicating cache partitions? [#47](https://github.com/cabol/nebulex/issues/47)
- Add support to define `:opts` in `defcacheable` and `defupdatable` [#40](https://github.com/cabol/nebulex/issues/40)
- Random test failure - UndefinedFunctionError [#28](https://github.com/cabol/nebulex/issues/28)
- Adapter for Memcached [#22](https://github.com/cabol/nebulex/issues/22)
- Invalidate keys cluster-wide [#18](https://github.com/cabol/nebulex/issues/18)

**Merged pull requests:**

- Fix error when running in a release [#41](https://github.com/cabol/nebulex/pull/41)
  ([peburrows](https://github.com/peburrows))

## [v1.0.1](https://github.com/cabol/nebulex/tree/v1.0.1) (2019-01-11)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.0...v1.0.1)

**Fixed bugs:**

- The `:infinity` atom is being set for unexpired object when is retrieved from
  an older generation [#37](https://github.com/cabol/nebulex/issues/37)

**Closed issues:**

- Caching utility macros: `defcacheable`, `defevict` and `defupdatable`
  [#39](https://github.com/cabol/nebulex/issues/39)
- Multilevel Cache: `replicate/2` is attempting to subtract from `:infinity`
  [#34](https://github.com/cabol/nebulex/issues/34)
- `has_key?/1` does not respect ttl [#33](https://github.com/cabol/nebulex/issues/33)
- Add dialyzer and credo checks to the CI pipeline [#31](https://github.com/cabol/nebulex/issues/31)
- Fix documentation about hooks [#30](https://github.com/cabol/nebulex/issues/30)
- FAQ list [#25](https://github.com/cabol/nebulex/issues/25)

**Merged pull requests:**

- typo in transaction docs [#38](https://github.com/cabol/nebulex/pull/38)
  ([fredr](https://github.com/fredr))
- Handle an :infinity expiration in multilevel replication.
  [#36](https://github.com/cabol/nebulex/pull/36) ([sdost](https://github.com/sdost))
- Add missing coma in conf section of readme file
  [#32](https://github.com/cabol/nebulex/pull/32) ([Kociamber](https://github.com/Kociamber))

## [v1.0.0](https://github.com/cabol/nebulex/tree/v1.0.0) (2018-10-31)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.0-rc.3...v1.0.0)

**Implemented enhancements:**

- Refactor `Nebulex.Adapters.Dist` to use `Task` instead of `:rpc` [#24](https://github.com/cabol/nebulex/issues/24)
- Create first cache generation by default when the cache is started [#21](https://github.com/cabol/nebulex/issues/21)

**Closed issues:**

- Performance Problem. [#27](https://github.com/cabol/nebulex/issues/27)
- Cache Failing to Start on Production [#26](https://github.com/cabol/nebulex/issues/26)
- Adapter for Redis [#23](https://github.com/cabol/nebulex/issues/23)
- For `update` and `get_and_update` functions, the :ttl is being overridden
  [#19](https://github.com/cabol/nebulex/issues/19)
- TTL and EXPIRE functions? [#17](https://github.com/cabol/nebulex/issues/17)
- Publish a rc.3 release [#16](https://github.com/cabol/nebulex/issues/16)
- Replicated cache adapter [#15](https://github.com/cabol/nebulex/issues/15)
- Fulfil the open-source checklist [#1](https://github.com/cabol/nebulex/issues/1)

## [v1.0.0-rc.3](https://github.com/cabol/nebulex/tree/v1.0.0-rc.3) (2018-01-10)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.0-rc.2...v1.0.0-rc.3)

**Closed issues:**

- Add stream [#10](https://github.com/cabol/nebulex/issues/10)

## [v1.0.0-rc.2](https://github.com/cabol/nebulex/tree/v1.0.0-rc.2) (2017-11-25)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.0-rc.1...v1.0.0-rc.2)

**Closed issues:**

- Atom exhaustion from generations [#8](https://github.com/cabol/nebulex/issues/8)
- Custom ttl for every cache record? [#7](https://github.com/cabol/nebulex/issues/7)
- Load/Stress Tests [#6](https://github.com/cabol/nebulex/issues/6)
- Update Getting Started guide [#4](https://github.com/cabol/nebulex/issues/4)
- Add counters support – increments and decrements by a given amount
  [#3](https://github.com/cabol/nebulex/issues/3)

## [v1.0.0-rc.1](https://github.com/cabol/nebulex/tree/v1.0.0-rc.1) (2017-07-30)

[Full Changelog](https://github.com/cabol/nebulex/compare/64dbc38a7e330bb15a1f7372c6d3a97b82d61cc4...v1.0.0-rc.1)

**Closed issues:**

- Implement mix task to automate cache generation [#2](https://github.com/cabol/nebulex/issues/2)



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
