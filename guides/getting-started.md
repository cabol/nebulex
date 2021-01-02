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
    {:nebulex, "2.0.0-rc.1"},
    {:shards, "~> 1.0"},      #=> When using :shards as backend
    {:decorator, "~> 1.3"},   #=> When using Caching Annotations
    {:telemetry, "~> 0.4"}    #=> When using the Telemetry events (Nebulex stats)
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

  * For enabling Telemetry events dispatched when using Nebulex stats you have
    to add `:telemetry` to the dependency list.
    See [telemetry guide][telemetry].

  * If you are using an adapter other than the built-in ones (e.g: Cachex or
    Redis adapters), you have to add that dependency too.

[nbx_caching]: http://hexdocs.pm/nebulex/Nebulex.Caching.html
[telemetry]: http://hexdocs.pm/nebulex/telemetry.html

To install these dependencies, we will run this command:

```
mix deps.get
```

For the second step, we need to define a Cache so that we can use it within the
application's code. Let's define `Blog.Cache` module within `lib/blog/cache.ex`:

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

Could be configured in `config/config.exs` like so:

```elixir
config :blog, Blog.Cache,
  gc_interval: :timer.seconds(3600),
  backend: :shards,
  partitions: 2
```

> By default, `partitions:` option is set to `System.schedulers_online()`.

**NOTE:** For more information about the provided options, see the adapter's
documentation.

The final piece of configuration is to setup the `Blog.Cache` as a
supervisor within the application's supervision tree, which we can do in
`lib/blog/application.ex` (or `lib/blog.ex` for elixir versions `< 1.4.0`),
inside the `start/2` function:

`Elixir < 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.Cache, [])
  ]

  ...
```

`Elixir >= 1.5.0`:

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

## Inserting entries

We can insert a new entries into our blog cache with this code:

```elixir
iex> user = %{id: 1, first_name: "Galileo", last_name: "Galilei"}
iex> Blog.Cache.put(user[:id], user, ttl: Nebulex.Time.expiry_time(1, :hour))
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

There is a function `has_key?` to check if a key exist in cache:

```elixir
iex> Blog.Cache.has_key?(1)
true

iex> Blog.Cache.has_key?(10)
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

### Flush

Nebulex also provides a function to flush all cache entries, like so:

```elixir
iex> Blog.Cache.flush()
_evicted_entries
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

### Cache size

To get the total number of cached objects:

```elixir
iex> Blog.Cache.size()
_num_cached_entries
```

## Query and/or Stream entries

Nebulex provides functions to fetch or stream all entries from cache matching
the given query.

To fetch all entries from cache:

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
# is a tuple `{key, value, version, expire_at}`, then the match spec
# could be something like:
iex> spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
iex> Blog.Cache.all(spec)
_all_matched

# using Ex2ms
iex> import Ex2ms
iex> spec =
...>   fun do
...>     {key, value, _, _} when value > 10 -> {key, value}
...>   end
iex> Blog.Cache.all(spec)
_all_matched
```

In the same way, we can stream all entries:

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

Let's define the `Blog.PartitionedCache` (`lib/blog/partitioned_cache.ex`)
like so:

```elixir
defmodule Blog.PartitionedCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Partitioned
end
```

> By default, the `primary_storage_adapter:` is set to `Nebulex.Adapters.Local`.

Could be configured with (`config/config.exs`):

```elixir
config :blog, Blog.PartitionedCache,
  primary: [
    gc_interval: :timer.seconds(3600),
    backend: :shards,
    partitions: 2
  ]
```

And remember to setup the `Blog.PartitionedCache` as supervisor within the
application's supervision tree (such as we did it previously):

`Elixir < 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.PartitionedCache, [])
  ]

  ...
```

`Elixir >= 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
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

First, let's define out multi-level cache `Blog.MultilevelCache`:

```elixir
defmodule Blog.MultilevelCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Multilevel

  defmodule L1 do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule L2 do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Partitioned
  end
end
```

Could be configured with (`config/config.exs`):

```elixir
config :blog, Blog.MultilevelCache,
  model: :inclusive,
  levels: [
    {
      Blog.MultilevelCache.L1,
      gc_interval: :timer.seconds(3600), backend: :shards
    },
    {
      Blog.MultilevelCache.L2,
      primary: [gc_interval: :timer.seconds(3600), backend: :shards]
    }
  ]
```

And remember to setup the `Blog.Multilevel` as a supervisor within the
application's supervision tree (such as we did it previously):

`Elixir < 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.MultilevelCache, [])
  ]

  ...
```

`Elixir >= 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    Blog.Multilevel
  ]

  ...
```

Let's try it out!

```elixir
iex> Blog.Multilevel.put("foo", "bar", ttl: Nebulex.Time.expiry_time(1, :hour))
"bar"

iex> Blog.Multilevel.get("foo")
"bar"
```

To learn more about how multilevel-cache works, please check
`Nebulex.Adapters.Multilevel` documentation, and also it is recommended see the
[near cache example](https://github.com/cabol/nebulex_examples/tree/master/near_cache)

## Next

 * [Cache Usage Patterns via Nebulex.Caching](http://hexdocs.pm/nebulex/cache-usage-patterns.html) -
   Annotations-based DSL to implement different cache usage patterns.
