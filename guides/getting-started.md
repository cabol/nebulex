# Getting Started

This guide is an introduction to [Nebulex](https://github.com/cabol/nebulex),
a local and distributed caching toolkit for Elixir. Nebulex API is pretty much
inspired by [Ecto](https://github.com/elixir-ecto/ecto), taking advantage of
its simplicity, flexibility and pluggable architecture. In the same way
as Ecto, developers can provide their own cache (adapter) implementations.

In this guide, we're going to learn some basics about Nebulex, such as insert,
retrieve and destroy cache entries.

## Adding Nebulex to an application

Let's start creating a new Elixir application by running this command:

```
mix new blog --sup
```

The `--sup` option ensures that this application has
[a supervision tree](http://elixir-lang.org/getting-started/mix-otp/supervisor-and-application.html),
which will be needed by Nebulex later on.

To add Nebulex to this application, there are a few steps that we need to take.

The first step will be adding Nebulex to our `mix.exs` file, which we'll do by
changing the `deps` definition in that file to this:

```elixir
defp deps do
  [
    {:nebulex, "~> 2.3"},
    {:shards, "~> 1.0"},      #=> When using :shards as backend
    {:decorator, "~> 1.4"},   #=> When using Caching Annotations
    {:telemetry, "~> 1.0"}    #=> When using the Telemetry events (Nebulex stats)
  ]
end
```

In order to give more flexibility and loading only needed dependencies, Nebulex
makes all its dependencies as optional. For example:

  * For intensive workloads, you may want to use `:shards` as the backend for
    the local adapter and having partitioned tables. In such a case, you have
    to add `:shards` to the dependency list.

  * For enabling the usage of
    [declarative annotation-based caching via decorators][nbx_caching],
    you have to add `:decorator` to the dependency list.

  * For enabling Telemetry events to be dispatched when using Nebulex,
    you have to add `:telemetry` to the dependency list.
    See [telemetry guide][telemetry].

  * If you want to use an external adapter (e.g: Cachex or Redis adapter), you
    have to add the adapter dependency too.

[nbx_caching]: http://hexdocs.pm/nebulex/Nebulex.Caching.html
[telemetry]: http://hexdocs.pm/nebulex/telemetry.html

To install these dependencies, we will run this command:

```
mix deps.get
```

We now need to define a Cache and setup some configuration for Nebulex so that
we can perform actions on a cache from within the application's code.

We can set up this configuration by running this command:

```
mix nbx.gen.cache -c Blog.Cache
```

This command will generate the configuration required to use the cache. The
first bit of configuration is in `config/config.exs`:

```elixir
config :blog, Blog.Cache,
  # When using :shards as backend
  # backend: :shards,
  # GC interval for pushing new generation: 12 hrs
  gc_interval: :timer.hours(12),
  # Max 1 million entries in cache
  max_size: 1_000_000,
  # Max 2 GB of memory
  allocated_memory: 2_000_000_000,
  # GC min timeout: 10 sec
  gc_cleanup_min_timeout: :timer.seconds(10),
  # GC min timeout: 10 min
  gc_cleanup_max_timeout: :timer.minutes(10)
```

Assuming we will use `:shards` as backend, can add uncomment the first line in
the config

```elixir
config :blog, Blog.Cache,
  # When using :shards as backend
  backend: :shards,
  # GC interval for pushing new generation: 12 hrs
  gc_interval: :timer.hours(12),
  # Max 1 million entries in cache
  max_size: 1_000_000,
  # Max 2 GB of memory
  allocated_memory: 2_000_000_000,
  # GC min timeout: 10 sec
  gc_cleanup_min_timeout: :timer.seconds(10),
  # GC min timeout: 10 min
  gc_cleanup_max_timeout: :timer.minutes(10)
```

> By default, `partitions:` option is set to `System.schedulers_online()`.

**NOTE:** For more information about the provided options, see the adapter's
documentation.

And the `Blog.Cache` module is defined in `lib/blog/cache.ex` by our
`mix nbx.gen.cache` command:

```elixir
defmodule Blog.Cache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Local
end
```

This module is what we'll be using to interact with the cache. It uses the
`Nebulex.Cache` module and it expects the `:otp_app` as option. The `otp_app`
tells Nebulex which Elixir application it can look for cache configuration in.
In this case, we've specified that it is the `:blog` application where Nebulex
can find that configuration and so Nebulex will use the configuration that was
set up in `config/config.exs`.

The final piece of configuration is to setup the `Blog.Cache` as a
supervisor within the application's supervision tree, which we can do in
`lib/blog/application.ex`, inside the `start/2` function:

```elixir
def start(_type, _args) do
  children = [
    Blog.Cache
  ]

  ...
```

This piece of configuration will start the Nebulex process which receives and
executes our application's commands. Without it, we wouldn't be able to use
the cache at all!

We've now configured our application so that it's able to execute commands
against our cache.

**IMPORTANT:** Make sure the cache is put in first place within the children
list, or at least before the process or processes using it. Otherwise, there
could be race conditions causing `Nebulex.RegistryLookupError` errors;
processes attempting to use the cache and this one hasn't been even
started.

## Inserting entries

We can insert a new entries into our blog cache with this code:

```elixir
iex> user = %{id: 1, first_name: "Galileo", last_name: "Galilei"}
iex> Blog.Cache.put(user[:id], user, ttl: :timer.hours(1))
:ok
```

To insert the data into our cache, we call `put` on `Blog.Cache`. This function
tells Nebulex that we want to insert a new key/value entry into the cache
corresponding `Blog.Cache`.

It is also possible to insert multiple entries at once:

```elixir
iex> users = %{
...>   1 => %{id: 1, first_name: "Galileo", last_name: "Galilei"},
...>   2 => %{id: 2, first_name: "Charles", last_name: "Darwin"},
...>   3 => %{id: 3, first_name: "Albert", last_name: "Einstein"}
...> }
iex> Blog.Cache.put_all(users)
:ok
```

> The given entries can be a `map` or a Key/Value tuple list.

### Inserting new entries and replacing existing ones

As we saw previously, `put` creates a new entry in cache if it doesn't exist,
or overrides it if it does exist (including the `:ttl`). However, there might
be circumstances where we want to set the entry only if it doesn't exit or the
other way around, this is where `put_new` and `replace` functions come in.

Let's try `put_new` and `put_new!` functions:

```elixir
iex> new_user = %{id: 4, first_name: "John", last_name: "Doe"}
iex> Blog.Cache.put_new(new_user.id, new_user, ttl: 900)
true

iex> Blog.Cache.put_new(new_user.id, new_user)
false

# same as previous one but raises `Nebulex.KeyAlreadyExistsError`
iex> Blog.Cache.put_new!(new_user.id, new_user)
```

Now `replace` and `replace!` functions:

```elixir
iex> existing_user = %{id: 5, first_name: "John", last_name: "Doe2"}
iex> Blog.Cache.replace(existing_user.id, existing_user)
false

iex> Blog.Cache.put_new(existing_user.id, existing_user)
true

iex> Blog.Cache.replace(existing_user.id, existing_user, ttl: 900)
true

# same as previous one but raises `KeyError`
iex> Blog.Cache.replace!(100, existing_user)
```

It is also possible to insert multiple new entries at once:

```elixir
iex> new_users = %{
...>   6 => %{id: 6, first_name: "Isaac", last_name: "Newton"},
...>   7 => %{id: 7, first_name: "Marie", last_name: "Curie"}
...> }
iex> Blog.Cache.put_new_all(new_users)
true

# none of the entries is inserted if at least one key already exists
iex> Blog.Cache.put_new_all(new_users)
false
```

## Retrieving entries

Let’s start off with fetching data by the key, which is the most basic and
common operation to retrieve data from a cache.

```elixir
iex> Blog.Cache.get(1)
_user_1

iex> for key <- 1..3 do
...>   user = Blog.Cache.get(key)
...>   user.first_name
...> end
["Galileo", "Charles", "Albert"]
```

There is a function `exists?` to check if a key exist in cache:

```elixir
iex> Blog.Cache.exists?(1)
true

iex> Blog.Cache.exists?(10)
false
```

Retrieving multiple entries

```elixir
iex> Blog.Cache.get_all([1, 2, 3])
_users
```

## Updating entries

Nebulex provides `update` and `get_and_update` functions to update an
entry value based on current one, for example:

```elixir
iex> initial = %{id: 1, first_name: "", last_name: ""}

# using `get_and_update`
iex> Blog.Cache.get_and_update(1, fn v ->
...>   if v, do: {v, %{v | first_name: "X"}}, else: {v, initial}
...> iex> end)
{_old, _updated}

# using `update`
iex> Blog.Cache.update(1, initial, &(%{&1 | first_name: "Y"}))
_updated
```

## Counters

The function `incr` is provided to increment or decrement a counter; by default,
a counter is initialized to `0`. Let's see how counters works:

```elixir
# by default, the counter is incremented by 1
iex> Blog.Cache.incr(:my_counter)
1

# but we can also provide a custom increment value
iex> Blog.Cache.incr(:my_counter, 5)
6

# to decrement the counter, just pass a negative value
iex> Blog.Cache.incr(:my_counter, -5)
1
```

## Deleting entries

We’ve now covered inserting, reading and updating entries. Now let's see how to
delete an entry using Nebulex.

```elixir
iex> Blog.Cache.delete(1)
:ok
```

### Take

This is another way not only for deleting an entry but also for retrieving it
before its delete it:

```elixir
iex> Blog.Cache.take(1)
_entry

# returns `nil` if `key` doesn't exist
iex> Blog.Cache.take("nonexistent")
nil

# same as previous one but raises `KeyError`
iex> Blog.Cache.take!("nonexistent")
```

## Info

The last thing we’ll cover in this guide is how to retrieve information about
cached objects or the cache itself.

### Remaining TTL

```elixir
iex> Blog.Cache.ttl(1)
_remaining_ttl

iex> Blog.Cache.ttl("nonexistent")
nil
```

## Query and/or Stream entries

Nebulex provides functions to fetch, count, delete, or stream all entries from
cache matching the given query.

### Fetch all entries from cache matching the given query

```elixir
# by default, returns all keys
iex> Blog.Cache.all()
_all_entries

# fetch all entries and return the keys
iex> Blog.Cache.all(nil, return: :key)
_keys

# built-in queries in `Nebulex.Adapters.Local` adapter
iex> Blog.Cache.all(nil)
iex> Blog.Cache.all(:unexpired)
iex> Blog.Cache.all(:expired)

# if we are using `Nebulex.Adapters.Local` adapter, the stored entry
# is a tuple `{:entry, key, value, touched, ttl}`, then the match spec
# could be something like:
iex> spec = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
iex> Blog.Cache.all(spec)
_all_matched

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {_, key, value, _, _} when value > 10 -> {key, value}
...>   end
iex> Blog.Cache.all(spec)
_all_matched
```

### Count all entries from cache matching the given query

For example, to get the total number of cached objects (cache size):

```elixir
iex> Blog.Cache.count_all()
_num_cached_entries
```

> By default, since none query is given to `count_all/2`, all entries
  in cache match.

In the same way as `all/2`, you can pass a query to count only the matched
entries:

```elixir
# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {_, value, _, _} when rem(value, 2) == 0 -> true
...>   end
iex> Blog.Cache.count_all(spec)
_num_of_matched_entries
```

> The previous example assumes you are using the built-in local adapter.

Also, if you are using the built-in local adapter, you can use the queries
`:expired` and `:unexpired` too, like so:

```elixir
iex> expired_entries = Blog.Cache.count_all(:expired)
iex> unexpired_entries = Blog.Cache.count_all(:unexpired)
```

### Delete all entries from cache matching the given query

Similar to `count_all/2`, Nebulex provides `delete_all/2` to not only count
the matched entries but also remove them from the cache at once, in one single
execution.

The first example is flushing the cache, delete all cached entries (which is
the default behavior when none query is provided):

```elixir
iex> Blog.Cache.delete_all()
_num_of_removed_entries
```

And just like `count_all/2`, you can also provide a custom query to delete only
the matched entries, or if you are using the built-in local adapter you can also
use the queries `:expired` and `:unexpired`. For example:

```elixir
iex> expired_entries = Blog.Cache.delete_all(:expired)
iex> unexpired_entries = Blog.Cache.delete_all(:unexpired)

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {_, value, _, _} when rem(value, 2) == 0 -> true
...>   end
iex> Blog.Cache.delete_all(spec)
_num_of_matched_entries
```

> These examples assumes you are using the built-in local adapter.

### Stream all entries from cache matching the given query

Similar to `all/2` but returns a lazy enumerable that emits all entries from the
cache matching the provided query.

If the query is `nil`, then all entries in cache match and are returned when the
stream is evaluated; based on the `:return` option.

```elixir
iex> Blog.Cache.stream()
iex> Blog.Cache.stream(nil, page_size: 100, return: :value)
iex> Blog.Cache.stream(nil, page_size: 100, return: :entry)

# using `Nebulex.Adapters.Local` adapter
iex> spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
iex> Blog.Cache.stream(spec)
_all_matched

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {key, value, _, _} when value > 10 -> {key, value}
...>   end
iex> Blog.Cache.stream(spec)
_all_matched
```

## Partitioned Cache

Nebulex provides the adapter `Nebulex.Adapters.Partitioned`, which allows to
set up a partitioned cache topology.

Let's set up the partitioned cache by using the `mix` task `mix nbx.gen.cache`:

```
mix nbx.gen.cache -c Blog.PartitionedCache -a Nebulex.Adapters.Partitioned
```

As we saw previously, this command will generate the cache in
`lib/bolg/partitioned_cache.ex` (in this case using the partitioned adapter)
module along with the initial configuration in `config/config.exs`.

The cache:

```elixir
defmodule Blog.PartitionedCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Partitioned,
    primary_storage_adapter: Nebulex.Adapters.Local
end
```

And the config:

```elixir
config :blog, Blog.PartitionedCache,
  primary: [
    # When using :shards as backend
    backend: :shards,
    # GC interval for pushing new generation: 12 hrs
    gc_interval: :timer.hours(12),
    # Max 1 million entries in cache
    max_size: 1_000_000,
    # Max 2 GB of memory
    allocated_memory: 2_000_000_000,
    # GC min timeout: 10 sec
    gc_cleanup_min_timeout: :timer.seconds(10),
    # GC min timeout: 10 min
    gc_cleanup_max_timeout: :timer.minutes(10)
  ]
```

And remember to add the new cache `Blog.PartitionedCache` to your application's
supervision tree (such as we did it previously):

```elixir
def start(_type, _args) do
  children = [
    Blog.Cache,
    Blog.PartitionedCache
  ]

  ...
```

Now we are ready to start using our partitioned cache!

### Timeout option

The `Nebulex.Adapters.Partitioned` supports `:timeout` option, it is a value in
milliseconds for the command that will be executed.

```elixir
iex> Blog.PartitionedCache.get("foo", timeout: 10)
_value

# if the timeout is exceeded, then the current process will exit
iex> Blog.PartitionedCache.put("foo", "bar", timeout: 10)
# ** (EXIT) time out
```

To learn more about how partitioned cache works, please check
`Nebulex.Adapters.Partitioned` documentation, and also it is recommended see the
[partitioned cache example](https://github.com/cabol/nebulex_examples/tree/master/partitioned_cache)

## Multilevel Cache

Nebulex also provides the adapter `Nebulex.Adapters.Multilevel`, which allows to
setup a multi-level caching hierarchy.

First, let's set up the multi-level cache by using the `mix` task
`mix nbx.gen.cache`:

```
mix nbx.gen.cache -c Blog.NearCache -a Nebulex.Adapters.Multilevel
```

By default, the command generates a 2-level near-cache topology. The first
level or `L1` using the built-in local adapter, and the second one or `L2`
using the built-in partitioned adapter.

The generated cache module `lib/blog/near_cache.ex`:

```elixir
defmodule Blog.NearCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Multilevel

  ## Cache Levels

  # Default auto-generated L1 cache (local)
  defmodule L1 do
    use Nebulex.Cache,
      otp_app: :blog,
      adapter: Nebulex.Adapters.Local
  end

  # Default auto-generated L2 cache (partitioned cache)
  defmodule L2 do
    use Nebulex.Cache,
      otp_app: :blog,
      adapter: Nebulex.Adapters.Partitioned
  end

  ## TODO: Add, remove or modify the auto-generated cache levels above
end
```

And the configuration (`config/config.exs`):

```elixir
config :blog, Blog.NearCache,
  model: :inclusive,
  levels: [
    # Default auto-generated L1 cache (local)
    {
      Blog.NearCache.L1,
      # GC interval for pushing new generation: 12 hrs
      gc_interval: :timer.hours(12),
      # Max 1 million entries in cache
      max_size: 1_000_000
    },
    # Default auto-generated L2 cache (partitioned cache)
    {
      Blog.NearCache.L2,
      primary: [
        # GC interval for pushing new generation: 12 hrs
        gc_interval: :timer.hours(12),
        # Max 1 million entries in cache
        max_size: 1_000_000
      ]
    }
  ]
```

> Remember you can add `backend: :shards` to use Shards as backend.

Finally, add the new cache `Blog.NearCache` to your application's supervision
tree (such as we did it previously):

```elixir
def start(_type, _args) do
  children = [
    Blog.Cache,
    Blog.PartitionedCache,
    Blog.NearCache
  ]

  ...
```

Let's try it out!

```elixir
iex> Blog.NearCache.put("foo", "bar", ttl: :timer.hours(1))
"bar"

iex> Blog.NearCache.get("foo")
"bar"
```

To learn more about how multilevel-cache works, please check
`Nebulex.Adapters.Multilevel` documentation, and also it is recommended see the
[near cache example](https://github.com/cabol/nebulex_examples/tree/master/near_cache)

## Next

 * [Cache Usage Patterns via Nebulex.Caching](http://hexdocs.pm/nebulex/cache-usage-patterns.html) -
   Annotations-based DSL to implement different cache usage patterns.
