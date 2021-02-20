# Migrating to v2.x

For the v2, Nebulex introduces several breaking changes, so this guide aims to
highlight most of these changes to make easier the transition to v2. Be aware
this guide won't focus on every change, just the most significant ones that can
affect how your application code interacts with the cache. Also, it is not a
detailed guide about how to translate the current code from older versions to
v2, just pointing out the areas the new documentation should be consulted on.

## Configuration

This is one of the biggest changes. Version 1.x, most of the configuration
options are resolved in compile-time, which has a lot of limitations.
Since version 2.x, only few arguments are configured in compile-time when
defining a cache, e.g.: `otp_app:`, `adapter:`, and `primary_storage_adapter:`
(for partitioned and replicated adapters). The rest of configuration parameters
are given via config file or at startup time. For more information and examples,
see `Nebulex.Cache`, `Nebulex.Adapters.Local`, `Nebulex.Adapters.Partitioned`,
`Nebulex.Adapters.Replicated`, `Nebulex.Adapters.Multilevel`.

## Cache API

There are several changes on the `Nebulex.Cache` API:

  * The `:return` option is not available anymore, so it has to be removed.
  * The `:version` option is not available anymore, so it has to be removed.
  * Callback `set/3` was refactored to `put/3`.
  * Callback `set_many/2` was refactored to `put_all/2`.
  * Callback `get_many/2` was refactored to `get_all/2`.
  * Callbacks `add/3` and `add!/3` were refactored to `put_new/3` and
    `put_new!/3`.
  * Callback `update_counter/3` was refactored to `incr/3` and `decr/3`.
  * Callback `add_or_replace/3` was removed.
  * Callback `object_info/2` was removed, and callbacks `ttl/1` and
    `touch/1` were added instead.

## Declarative annotation-based caching via decorators

  * Module `Nebulex.Caching.Decorators` was refactored to `Nebulex.Caching` –
    Keep in mind that since v1.2.x the caching decorators were included instead
    of the previous macros or DSL (this applies for version lower than v1.1.x).
  * Decorator `cache/3` was refactored to `cacheable/3`.
  * Decorator `evict/3` was refactored to `cache_evict/3`.
  * Decorator `update/3` was refactored to `cache_put/3`.
  * Improved the `:match` option to return not only a boolean but return a
    specific value to be cached `(term -> boolean | {true, term})` – If `true`
    the code-block evaluation result is cached as it is (the default). If
    `{true, value}` is returned, then the `value` is what is cached.

## Hooks

Since v2.x, pre/post hooks are deprecated and won't be longer supported by
`Nebulex`, at least not directly. Mainly, because the hooks feature is not a
common use-case and also it is something that can be be easily implemented
on top of the Cache at the application level. However, to keep backward
compatibility somehow, `Nebulex` provides decorators for implementing
pre/post hooks very easily. For that reason, it is highly recommended
to removed all pre/post hooks related code and adapt it to the new way.
See `Nebulex.Hook` for more information.

## Built-In Adapters

There have been several and significant improvements on the built-in adapters,
so it is also highly recommended to take a look at them;
`Nebulex.Adapters.Local`, `Nebulex.Adapters.Partitioned`,
`Nebulex.Adapters.Replicated`, and `Nebulex.Adapters.Multilevel`.

In case of using a distributed adapter, the module `Nebulex.Adapter.HashSlot`
was refactored to `Nebulex.Adapter.Keyslot` and the callback `keyslot /2` to
`hash_slot/2`.

## Statistics

For older versions (<= 1.x), the stats were implemented via a post-hook and the
measurements were oriented for counting the number of times a cache function is
called. But what is interesting and useful to see is, for instance, the number
of writes, hits, misses, evictions, etc. Therefore, the whole stats'
functionality was refactored entirely.

  1. This feature is not longer using pre/post hooks. Besides, pre/post hooks
     are deprecated in v2.x.
  2. The stats support is optional by implementing the `Nebulex.Adapter.Stats`
     behaviour from the adapter. However, Nebulex provides a default
     implementation using [Erlang counters][https://erlang.org/doc/man/counters.html]
     which is supported by the local built-in adapter.
     See the [Telemetry guide](http://hexdocs.pm/nebulex/telemetry.html) for
     more information.
  3. Since Nebulex 2.x on-wards, enabling stats is a matter of setting the
     option `:stats` to `true`. See `Nebulex.Cache` for more information.

## Mix Tasks

  * `mix nebulex.gen.cache` was refactored to `mix nbx.gen.cache`.
  * `mix nebulex` was refactored to `mix nbx`.
