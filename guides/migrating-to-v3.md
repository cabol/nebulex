# Migrating to v3.x

For the v3, Nebulex introduces several breaking changes, including the Cache
API itself. This guide aims to highlight most of these changes to make easier
the transition to v3. Be aware this guide won't focus on every change, just
the most significant ones that can affect how your application code interacts
with the cache. Also, it is not a detailed guide about how to translate the
current code from older versions to v3, just pointing out the areas the new
documentation should be consulted on.

## Built-In Adapters

All previously built-in adapters (`Nebulex.Adapters.Local`,
`Nebulex.Adapters.Partitioned`, `Nebulex.Adapters.Replicated`, and
`Nebulex.Adapters.Multilevel`) have been moved to separate repositories.
Therefore, you must add the adapter dependency to the list of dependencies
in your `mix.exs` file.

## Cache API

The most significant change is on the [Cache API][cache_api]. Nebulex v3 has a
new API based on ok/error tuples.

Nebulex v3 brings a new API with two flavors:

* An ok/error tuple API for all cache functions. This new approach is preferred
  when you want to handle different outcomes using pattern-matching.
* An alternative API version with trailing bang (`!`) functions. This approach
  is preferred if you expect the outcome to always be successful.

[cache_api]: https://hexdocs.pm/nebulex/Nebulex.Cache.html

### Migrating to the new API

There are two ways to address the API changes. The first is to review all the
cache calls in your code and handle the new ok/error tuple response.
For example, wherever you were calling:

```elixir
:ok = MyApp.Cache.put("key", "value")

value = MyApp.Cache.get("key")
```

Now you should change it to handle the ok/error response, like so:

```elixir
case MyApp.Cache.put("key", "value") do
  :ok ->
    #=> your logic handling success

  {:error, reason} ->
    #=> your logic handling the error
end

case MyApp.Cache.get("key") do
  {:ok, value} ->
    #=> your logic handling success

  {:error, reason} ->
    #=> your logic handling the error
end
```

The same applies to ALL the Cache API functions. For this reason, it is highly
recommended you check your code and add the proper changes based on the new
ok/error tuple API.

The second way to address the API changes (and perhaps the easiest one) is to
replace your cache calls by using the function version with the trailing bang
(`!`). For example, wherever you were calling:

```elixir
:ok = MyApp.Cache.put("key", "value")

value = MyApp.Cache.get("key")
```

You could change it to:

```elixir
:ok = MyApp.Cache.put!("key", "value")

value = MyApp.Cache.get!("key")
```

As you may notice, the new Cache API exposes ok/error functions, as well as
bang functions (`!`) to give more flexibility to the users; now you can decide
whether you like to handle the errors or not.

> #### DISCLAIMER {: .warning}
> Despite this fix of using bang functions (`!`) may work for most cases, there
> may be a few where the outcome is not the same or the patch is just not
> applicable. Hence, it is recommended to review carefully the
> [Cache API docs][cache_api] anyway.

### API changes

The following are some of the changes you should be aware of:

* `Nebulex.Adapter.Stats` behaviour is deprecated. Therefore, the stats
  callbacks `stats/0` and `dispatch_stats/1` are no longer available and must
  be removed from your code. As an alternative, see the **"Info API"** section
  down below.
* `Nebulex.Adapter.Persistence` behaviour is deprecated. Therefore, the
  callbacks `dump/2` and `load/2` are no longer available and must be removed
  from your code. Persistence can be implemented in many different ways
  depending on the use case. A persistence API with a specific implementation
  may not be very useful because it won't cover all possible use cases. For
  example, if your application is on AWS, perhaps it makes more sense to use S3
  as persistent storage, not the local file system. Since Nebulex v3,
  persistence is an add-on that can be provided by the backend (e.g., Redis),
  another library, or the application itself. And it should be configured via
  the adapter's configuration (or maybe directly with the backend).
* The callback `flush/0` is deprecated, you should use `delete_all/2`
  instead (e.g., `MyApp.Cache.delete_all()`).
* The callback `all/2` was merged into `get_all/2`; only the latter can be
  used now. The new version of `get_all/2` accepts a query-spec as a first
  argument. For example, wherever you were doing `MyApp.get_all([k1, k2, ...])`,
  you must change it to `MyApp.get_all(in: [k1, k2, ...])`. Similarly, wherever
  you were doing `MyApp.all(some_query)`, you must change it to
  `MyApp.get_all(query: some_query)`.
* Regarding the previous change, the option `:return` is deprecated. Overall,
  for all "Query API" callbacks, is recommended to see the documentation to be
  aware of the new query specification and available options.
* The previous callback `get/2` has changed the semantics a bit (aside from
  the ok/error tuple API). Previously, it did return `nil` when the given key
  wasn't in the cache. Now, the callback accepts an argument to specify the
  default value when the key is not found.

### Info API

Since Nebulex v3, the adapter's Info API is introduced. This is a more generic
API to get information about the cache, including the stats. Adapters are
responsible for implementing the Info API and are also free to add the
information specification keys they want. See
[c:Nebulex.Cache.info/2][info_cb] and the ["Cache Info Guide"][cache_info_guide]
for more information.

[info_cb]: https://hexdocs.pm/nebulex/Nebulex.Cache.html#c:info/2
[cache_info_guide]: https://hexdocs.pm/nebulex/cache-info.html

## `nil` values

Previously, Nebulex used to skip storing `nil` values in the cache. The main
reason is the semantics the `nil` value had behind, being used to validate
whether a key existed in the cache or not. However, this is a limitation too.

Since Nebulex v3, any Elixir term can be stored in the cache (including `nil`),
Nebulex doesn't perform any validation whatsoever. Any meaning or semantics
behind `nil` (or any other term) is up to the user.

Additionally, a new callback `fetch/2` is introduced, which is the base or
main function for retrieving a key from the cache; in fact, the `get` callback
is implemented using `fetch` underneath.

## Caching decorators (declarative caching)

Nebulex v3 introduces some changes and new features to the Declarative Caching
API (a.k.a caching decorators). We will highlight mostly the changes and perhaps
a few new features. However, it is highly recommended you check the
documentation for more information about all the new features and changes.

* The `:cache` option can be set globally for all decorated functions in a
  module when defining the caching usage via `use Nebulex.Caching`. For example:
  `use Nebulex.Caching, cache: MyApp.Cache`. In that way, you don't need to add
  the cache to all decorated functions, unless the cache for some of them is
  different or when using references to an external cache.
* The `:cache` option doesn't support MFA tuples anymore. The possible values
  are a cache module, a dynamic cache spec, or an anonymous function that
  receives the decorator's context as an argument and must return the cache
  to use (a cache module or a dynamic cache spec).
* The `:key_generator` option is deprecated. Instead, you can use the `:key`
  option with an anonymous function that receives the decorator's context as an
  argument and must return the key to use.
* The `Nebulex.Caching.KeyGenerator` behaviour is deprecated. You can use
  an anonymous function for the `:default_key_generator` option
  (the function must be provided in the format `&Mod.fun/arity`).
* The `:default_key_generator` option must be defined when using
  `Nebulex.Caching`. For example:
  `use Nebulex.Caching, default_key_generator: &MyApp.generate_key/1`.
* The `:references` option in the `cacheable` decorator supports a reference
  to a dynamic cache.
* The option `:keys` is deprecated. Instead, consider using the option `:key`
  like this: `key: {:in, [...]}`.

> See ["Caching Decorators"][caching_decorators] for more info.

[caching_decorators]: https://hexdocs.pm/nebulex/Nebulex.Caching.Decorators.html
