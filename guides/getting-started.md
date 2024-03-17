# Getting Started

This guide is an introduction to [Nebulex](https://github.com/cabol/nebulex),
a local and distributed caching toolkit for Elixir. Nebulex API is pretty much
inspired by [Ecto](https://github.com/elixir-ecto/ecto), taking advantage of
its simplicity, flexibility and pluggable architecture. Same as Ecto,
developers can provide their own cache (adapter) implementations.

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

The first step will be adding both Nebulex and the cache adapter as a dependency
to our `mix.exs` file, which we'll do by changing the `deps` definition in that
file to this:

```elixir
defp deps do
  [
    {:nebulex, "~> 3.0"},
    {:nebulex_adapters_local, "~> 3.0"},
    #=> When using :shards as backend for local adapter
    {:shards, "~> 1.1"},
    #=> When using Caching decorators (recommended adding it)
    {:decorator, "~> 1.4"},
    #=> When using the Telemetry events (recommended adding it)
    {:telemetry, "~> 1.0"}
  ]
end
```

To give more flexibility and load only needed dependencies, Nebulex makes all
dependencies optional, including the adapters. For example:

  * For intensive workloads when using `Nebulex.Adapters.Local` adapter, you may
    want to use `:shards` as the backend for partitioned ETS tables. In such a
    case, you have to add `:shards` to the dependency list.

  * For enabling [declarative decorator-based caching][nbx_caching], you have
    to add `:decorator` to the dependency list.

  * For enabling Telemetry events dispatched by Nebulex, you have to add
    `:telemetry` to the dependency list. See [telemetry guide][telemetry].

[nbx_caching]: http://hexdocs.pm/nebulex/Nebulex.Caching.Decorators.html
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
  # GC max timeout: 10 min
  gc_cleanup_max_timeout: :timer.minutes(10)
```

Assuming you want to use `:shards` as backend, uncomment the `backend:` option:

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
  # GC max timeout: 10 min
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
could be race conditions causing exceptions or errors `Nebulex.Error`
(with reason `:registry_lookup_error`); processes attempting to use
the cache and this one hasn't been even started.

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
{:ok, true}

iex> Blog.Cache.put_new(new_user.id, new_user)
{:ok, false}

# same as previous one but raises `Nebulex.Error` in case of error
iex> Blog.Cache.put_new!(new_user.id, new_user)
false
```

Now `replace` and `replace!` functions:

```elixir
iex> existing_user = %{id: 5, first_name: "John", last_name: "Doe2"}
iex> Blog.Cache.replace(existing_user.id, existing_user)
{:ok, false}

iex> Blog.Cache.put_new(existing_user.id, existing_user)
{:ok, true}

iex> Blog.Cache.replace(existing_user.id, existing_user, ttl: 900)
{:ok, true}

# same as previous one but raises `Nebulex.Error` in case of error
iex> Blog.Cache.replace!(existing_user.id, existing_user)
true

iex> Blog.Cache.replace!("unknown", existing_user)
false
```

It is also possible to insert multiple new entries at once:

```elixir
iex> new_users = %{
...>   6 => %{id: 6, first_name: "Isaac", last_name: "Newton"},
...>   7 => %{id: 7, first_name: "Marie", last_name: "Curie"}
...> }
iex> Blog.Cache.put_new_all(new_users)
{:ok, true}

# none of the entries is inserted if at least one key already exists
iex> Blog.Cache.put_new_all(new_users)
{:ok, false}

# same as previous one but raises `Nebulex.Error` in case of error
iex> Blog.Cache.put_new_all!(new_users)
false
```

## Retrieving entries

Let’s start off with fetching data by the key, which is the most basic and
common operation to retrieve data from a cache.

```elixir
# Using `fetch` callback
iex> {:ok, user1} = Blog.Cache.fetch(1)
iex> user1.id
1

# If the key doesn't exist an error tuple is returned
iex> {:error, %Nebulex.KeyError{} = e} = Blog.Cache.fetch("unknown")
iex> e.key
"unknown"

# Using `fetch!` (same as `fetch` but raises an exception in case of error)
iex> user1 = Blog.Cache.fetch!(1)
iex> user1.id
1

# Using `get` callback (returns the default in case the key doesn't exist)
iex> {:ok, user1} = Blog.Cache.get(1)
iex> user1.id
1

# Returns the default because the key doesn't exist
iex> Blog.Cache.get("unknown")
{:ok, nil}
iex> Blog.Cache.get("unknown", "default")
{:ok, "default"}

# Using `get!` (same as `get` but raises an exception in case of error)
iex> user1 = Blog.Cache.get!(1)
iex> user1.id
1
iex> Blog.Cache.get!("unknown")
nil
iex> Blog.Cache.get!("unknown", "default")
"default"

iex> for key <- 1..3 do
...>   user = Blog.Cache.get!(key)
...>   user.first_name
...> end
["Galileo", "Charles", "Albert"]
```

There is a function `has_key?` to check if a key exist in cache:

```elixir
iex> Blog.Cache.has_key?(1)
{:ok, true}

iex> Blog.Cache.has_key?(10)
{:ok, false}
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
{:ok, {_old, _updated}}

# using `update`
iex> Blog.Cache.update(1, initial, &(%{&1 | first_name: "Y"}))
{:ok, _updated}
```

> You can also use the version with the trailing bang (`!`) `get_and_update!`
> and `!update`.

## Counters

The function `incr` is provided to increment or decrement a counter; by default,
a counter is initialized to `0`. Let's see how counters works:

```elixir
# by default, the counter is incremented by 1
iex> Blog.Cache.incr(:my_counter)
{:ok, 1}

# but we can also provide a custom increment value
iex> Blog.Cache.incr(:my_counter, 5)
{:ok, 6}

# to decrement the counter, just pass a negative value
iex> Blog.Cache.incr(:my_counter, -5)
{:ok, 1}

# using `incr!`
iex> Blog.Cache.incr!(:my_counter)
2
```

## Deleting entries

We’ve now covered inserting, reading and updating entries. Now let's see how to
delete an entry using Nebulex.

```elixir
iex> Blog.Cache.delete(1)
:ok

# or `delete!`
iex> Blog.Cache.delete!(1)
:ok
```

### Take

This is another way not only for deleting an entry but also for retrieving it
before its delete it:

```elixir
iex> Blog.Cache.take(1)
{:ok, _entry}

# If the key doesn't exist an error tuple is returned
iex> {:error, %Nebulex.KeyError{} = e} = Blog.Cache.take("nonexistent")
iex> e.key
"nonexistent"

# same as previous one but raises `Nebulex.KeyError`
iex> Blog.Cache.take!("nonexistent")
```

## Entry expiration

You can get the remaining TTL or expiration time for a key like so:

```elixir
# If no TTL is set when the entry is created, `:infinity` is set by default
iex> Blog.Cache.ttl(1)
{:ok, :infinity}

# If the key doesn't exist an error tuple is returned
iex> {:error, %Nebulex.KeyError{} = e} = Blog.Cache.ttl("nonexistent")
iex> e.key
"nonexistent"

# Same as `ttl` but an exception is raised if an error occurs
iex> Blog.Cache.ttl!(1)
:infinity
```

You could also change or update the expiration time using `expire`, like so:

```elixir
iex> Blog.Cache.expire(1, :timer.hours(1))
{:ok, true}

# When the key doesn't exist false is returned
iex> Blog.Cache.expire("nonexistent", :timer.hours(1))
{:ok, false}

# Same as `expire` but an exception is raised if an error occurs
iex> Blog.Cache.expire!(1, :timer.hours(1))
true
```

## Query and/or Stream entries

Nebulex provides functions to fetch, count, delete, or stream all entries from
cache matching the given query.

### Fetch all entries from cache matching the given query

```elixir
# by default, returns all entries
iex> Blog.Cache.get_all() #=> The query is set to nil by default
{:ok, _all_entries}

# fetch all entries and return the keys
iex> Blog.Cache.get_all(select: :key)
{:ok, _all_keys}

# fetch all entries and return the values
iex> Blog.Cache.get_all(select: :value)
{:ok, _all_values}

# fetch entries associated to the requested keys
iex> Blog.Cache.get_all(in: [1, 2])
{:ok, _fetched_entries}

# raises an exception in case of error
iex> Blog.Cache.get_all!()
_all_entries

# raises an exception in case of error
iex> Blog.Cache.get_all!(in: [1, 2])
_fetched_entries

# built-in queries in `Nebulex.Adapters.Local` adapter
iex> Blog.Cache.get_all() #=> Equivalent to Blog.Cache.get_all(query: nil)
iex> Blog.Cache.get_all(query: :expired)

# if we are using `Nebulex.Adapters.Local` adapter, the stored entry
# is a tuple `{:entry, key, value, touched, ttl}`, then the match spec
# could be something like:
iex> spec = [{{:_, :"$1", :"$2", :_, :_}, [{:>, :"$1", 10}], [{{:"$1", :"$2"}}]}]
iex> Blog.Cache.get_all(query: spec)
{:ok, _all_matched}

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {_, key, value, _, _} when key > 10 -> {key, value}
...>   end
iex> Blog.Cache.get_all(query: spec)
{:ok, _all_matched}
```

### Count all entries from cache matching the given query

For example, to get the total number of cached objects (cache size):

```elixir
# by default, counts all entries
iex> Blog.Cache.count_all() #=> The query is set to nil by default
{:ok, _num_cached_entries}

# raises an exception in case of error
iex> Blog.Cache.count_all!()
_num_cached_entries
```

Similar to `get_all`, you can pass a query to count only the matched entries.
For example, `Blog.Cache.count_all(query: query)`.

### Delete all entries from cache matching the given query

Similar to `count_all/2`, Nebulex provides `delete_all/2` to not only count
the matched entries but also remove them from the cache at once, in one single
execution.

The first example is flushing the cache, delete all cached entries (which is
the default behavior when none query is provided):

```elixir
iex> Blog.Cache.delete_all()
{:ok, _num_of_removed_entries}

# raises an exception in case of error
iex> Blog.Cache.delete_all!()
_num_of_removed_entries
```

One may also delete a list of keys at once (like a bulk delete):

```elixir
iex> Blog.Cache.delete_all(in: ["k1", "k2"])
{:ok, _num_of_removed_entries}

# raises an exception in case of error
iex> Blog.Cache.delete_all!(in: ["k1", "k2"])
_num_of_removed_entries
```

### Stream all entries from cache matching the given query

Similar to `get_all` but returns a lazy enumerable that emits all entries from
the cache matching the provided query.

If the query is `nil`, then all entries in cache match and are returned when the
stream is evaluated (based on the `:select` option).

```elixir
iex> {:ok, stream} = Blog.Cache.stream()
iex> Enum.to_list(stream)
_all_matched

iex> {:ok, stream} = Blog.Cache.stream(select: :key)
iex> Enum.to_list(stream)
_all_matched

iex> {:ok, stream} = Blog.Cache.stream([select: :value], max_entries: 100)
iex> Enum.to_list(stream)
_all_matched

# raises an exception in case of error
iex> stream = Blog.Cache.stream!()
iex> Enum.to_list(stream)
_all_matched

# using `Nebulex.Adapters.Local` adapter
iex> spec = [{{:entry, :"$1", :"$2", :_, :_}, [{:<, :"$1", 3}], [{{:"$1", :"$2"}}]}]
iex> {:ok, stream} = Blog.Cache.stream(query: spec)
iex> Enum.to_list(stream)
_all_matched

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {:entry, key, value, _, _} when key < 3 -> {key, value}
...>   end
iex> {:ok, stream} = Blog.Cache.stream(query: spec)
iex> Enum.to_list(stream)
_all_matched
```

## Partitioned Cache

Nebulex provides the adapter `Nebulex.Adapters.Partitioned`, which allows to
set up a partitioned cache topology. First of all, we need to add
`:nebulex_adapters_partitioned` to the dependencies in the `mix.exs`:

```elixir
defp deps do
  [
    {:nebulex, "~> 3.0"},
    {:nebulex_adapters_local, "~> 3.0"},
    {:nebulex_adapters_partitioned, "~> 3.0"},
    #=> When using :shards as backend for local adapter
    {:shards, "~> 1.0"},
    #=> When using Caching decorators (recommended adding it)
    {:decorator, "~> 1.4"},
    #=> When using the Telemetry events (recommended adding it)
    {:telemetry, "~> 1.0"}
  ]
end
```

Let's set up the partitioned cache by using the `mix` task
`mix nbx.gen.cache.partitioned`:

```
mix nbx.gen.cache.partitioned -c Blog.PartitionedCache
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
    # GC max timeout: 10 min
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
#=> {:ok, value}

# when the command's call timed out an error is returned
iex> Blog.PartitionedCache.put("foo", "bar", timeout: 10)
#=> {:error, %Nebulex.Error{reason: :timeout}}
```

To learn more about how partitioned cache works, please check
`Nebulex.Adapters.Partitioned` documentation, and also it is recommended see the
[partitioned cache example](https://github.com/cabol/nebulex_examples/tree/master/partitioned_cache)

## Multilevel Cache

Nebulex also provides the adapter `Nebulex.Adapters.Multilevel`, which allows to
setup a multi-level caching hierarchy.

Same as any other adapter, we have to add `:nebulex_adapters_multilevel` to the
dependencies in the `mix.exs`:

```elixir
defp deps do
  [
    {:nebulex, "~> 3.0"},
    {:nebulex_adapters_local, "~> 3.0"},
    {:nebulex_adapters_partitioned, "~> 3.0"},
    {:nebulex_adapters_multilevel, "~> 3.0"},
    #=> When using :shards as backend for local adapter
    {:shards, "~> 1.0"},
    #=> When using Caching decorators (recommended adding it)
    {:decorator, "~> 1.4"},
    #=> When using the Telemetry events (recommended adding it)
    {:telemetry, "~> 1.0"}
  ]
end
```

Let's set up the multilevel cache by using the `mix` task
`mix nbx.gen.cache.multilevel`:

```
mix nbx.gen.cache.multilevel -c Blog.NearCache
```

By default, the command generates a 2-level near-cache topology. The first
level or `L1` using `Nebulex.Adapters.Local` adapter, and the second one or `L2`
using `Nebulex.Adapters.Partitioned` adapter.

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
:ok

iex> Blog.NearCache.get!("foo")
"bar"
```

To learn more about how multilevel-cache works, please check
`Nebulex.Adapters.Multilevel` documentation, and also it is recommended see the
[near cache example](https://github.com/cabol/nebulex_examples/tree/master/near_cache)

## Next

* [Decorators-based DSL for cache usage patterns][cache-usage-patterns].

[cache-usage-patterns]: http://hexdocs.pm/nebulex/cache-usage-patterns.html
