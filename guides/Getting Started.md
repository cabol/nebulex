# Getting Started

This guide is an introduction to [Nebulex](https://github.com/cabol/nebulex),
a local and distributed caching tool for Elixir. Nebulex API is pretty much
inspired by [Ecto](https://github.com/elixir-ecto/ecto), taking advantage of
its simple interface, flexible and pluggable architecture. In the same way
as Ecto, developers can provide their own Cache implementations.

Additionally, Nebulex provides three adapter implementations built-in:

Nebulex Adapter               | Description
:---------------------------- | :-----------------------
`Nebulex.Adapters.Local`      | Local Generational Cache
`Nebulex.Adapters.Dist`       | Distributed Cache
`Nebulex.Adapters.Multilevel` | Multi-level Cache

In this guide, we're going to learn some basics about Nebulex, such as set,
retrieve and destroy cache entries (key/value pairs).

## Adding Nebulex to an application

Let's start creating a new Elixir application by running this command:

```
mix new blog --sup
```

The `--sup` option ensures that this application has [a supervision tree](http://elixir-lang.org/getting-started/mix-otp/supervisor-and-application.html),
which will be needed by Nebulex later on.

To add Nebulex to this application, there are a few steps that we need to take.

The first step will be adding Nebulex to our `mix.exs` file, which we'll do by
changing the `deps` definition in that file to this:

```elixir
defp deps do
  [{:nebulex, "~> 1.0.0-rc.1"}]
end
```

To install these dependencies, we will run this command:

```
mix deps.get
```

For the second step we need to setup some configuration for Nebulex so that we
can perform actions on a cache from within the application's code.

We can set up this configuration by running this command:

```
mix nebulex.gen.cache -c Blog.Cache
```

This command will generate the configuration required to use our cache.
The first bit of configuration is in `config/config.exs`:

```elixir
config :blog, Blog.Cache,
  adapter: Nebulex.Adapters.Local,
  gc_interval: 86_400 # 24 hrs
```

The `Blog.Cache` module is defined in `lib/blog/cache.ex` by our
`mix nebulex.gen.cache` command:

```elixir
defmodule Blog.Cache do
  use Nebulex.Cache, otp_app: :blog
end
```

This module is what we'll be using to interact with the cache. It uses the
`Nebulex.Cache` module, and the `otp_app` tells Nebulex which Elixir application
it can look for cache configuration in. In this case, we've specified that it is
the `:blog` application where Nebulex can find that configuration and so Nebulex
will use the configuration that was set up in `config/config.exs`.

The final piece of configuration is to setup the `Blog.Cache` as a
supervisor within the application's supervision tree, which we can do in
`lib/blog/application.ex` (or `lib/blog.ex` for elixir versions `< 1.4.0`),
inside the `start/2` function:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.Cache, []),
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
data = %{id: 1, text: "hello"}

Blog.Cache.set(data[:id], data)
```

To insert the data into our cache, we call `set` on `Blog.Cache`. This function
tells Nebulex that we want to insert a new key/value entry into the cache
corresponding `Blog.Cache`.

A successful set will return (by default) the inserted value, like so:

```elixir
%{id: 1, text: "hello"}
```

But, using the option `:return` we can ask for return either the value, key or
the entire `Nebulex.Object`, like so:

```elixir
Blog.Cache.set("foo", "bar", return: :key)

Blog.Cache.set("foo", "bar", return: :object)

Blog.Cache.set("foo", "bar", return: :value) # Default
```

## Retrieving entries

First, let's create some data as we learned before.

```elixir
people = [
  %{id: 1, first_name: "Galileo", last_name: "Galilei"},
  %{id: 2, first_name: "Charles", last_name: "Darwin"},
  %{id: 3, first_name: "Albert", last_name: "Einstein"}
]

Enum.each(people, fn(person) -> Blog.Cache.set(person[:id], person) end)
```

This code will create three new people in our cache.

### Fetching a single entry

Let’s start off with fetching data by the key, which is the most basic and
common operation to retrieve data from a cache.

```elixir
Blog.Cache.get(1)

for key <- 1..3, do: Blog.Cache.get(key)
```

By default, `get` returns the value associated to the given key, but in the same
way as `set`, we can ask for return either the key, value or object.

```elixir
for key <- 1..3, do: Blog.Cache.get(key, return: :key)

for key <- 1..3, do: Blog.Cache.get(key, return: :object)
```

Additionally, there is a function `has_key?` to check if a key exist in cache:

```elixir
Blog.Cache.has_key? 1
```

It returns `true` if the ket exist and `false` otherwise.

### Fetching all entries

To fetch all entries from cache, Nebulex provides `to_map` function:

```elixir
Blog.Cache.to_map
```

By default, it returns all values, but gain, you can request to return the objects.

```elixir
Blog.Cache.to_map(return: :object)
```

## Updating entries

Updating entries in Nebulex can be achieved in different ways. The basic one,
using `get` and `set` (the basic functions), like so:

```elixir
v1 = Blog.Cache.get(1)

Blog.Cache.set(1, %{v1 | first_name: "Nebulex"})

# In case you don't care about an existing entry, you can just override the
# existing one (if it exists); remember, `set` is an idempotent operation
Blog.Cache.set(1, "anything")
```

Besides, Nebulex provides `update` and `get_and_update` functions to
update entries, for example:

```elixir
initial = %{id: 1, first_name: "", last_name: ""}

# using `get_and_update`
Blog.Cache.get_and_update(1, fn v ->
  if v, do: {v, %{v | first_name: "X"}}, else: {v, initial}
end)

# using `update`
Blog.Cache.update(1, initial, &(%{&1 | first_name: "Y"}))
```

## Updating counters

Nebulex also provides the function `update_counter` in order to handle counters,
increments and decrements; by default, a counter is set/initialized to `0`.
Let's see how counters works:

```elixir
# by default, the counter is incremented by 1
Blog.Cache.update_counter(:my_counter)

# but we can also provide a custom increment value
Blog.Cache.update_counter(:my_counter, 5)

# to decrement the counter, just pass a negative value
Blog.Cache.update_counter(:my_counter, -5)
```

## Deleting entries

We’ve now covered inserting (`set`), reading (`get`, `get!`, `all`) and updating
entries. The last thing that we’ll cover in this guide is how to delete an entry
using Nebulex.

```elixir
Blog.Cache.delete(1)
```

It always returns the `key` either if success or not, therefore, the option
`:return` has not any effect.

There is another way to delete an entry and at the same time to retrieve it,
the function to achieve this is `pop`, this is an example:

```elixir
Blog.Cache.pop(1)

Blog.Cache.pop(2, return: :key)

Blog.Cache.pop(3, return: :object)
```

Similar to `set` and `get`, `pop` returns the value by default, but you can
request to return either the key, value or object.

## Distributed Cache

Nebulex provides the adapter `Nebulex.Adapters.Dist`, which allows to setup a
distributed cache.

Let's setup our distributed cache by running this command:

```
mix nebulex.gen.cache -c Blog.DistCache -a Nebulex.Adapters.Dist
```

This command will generate the configuration required to use our distributed
cache. Within the `config/config.exs`:

```elixir
config :blog, Blog.DistCache,
  adapter: Nebulex.Adapters.Dist,
  local: :YOUR_LOCAL_CACHE,
  node_picker: Nebulex.Adapters.Dist
```

Replace the `local` config value `:YOUR_LOCAL_CACHE` by an existing local cache,
for example, we can set the local cache we created previously or create a new
one. Let's create a new one:

```
mix nebulex.gen.cache -c Blog.LocalCache
```

Now let's replace the `local` config value `:YOUR_LOCAL_CACHE` by our new local
cache:

```elixir
config :blog, Blog.DistCache,
  adapter: Nebulex.Adapters.Dist,
  local: Blog.LocalCache,
  node_picker: Nebulex.Adapters.Dist
```

The `Blog.DistCache` module is defined in `lib/blog/dist_cache.ex` by our
`mix nebulex.gen.cache` command:

```elixir
defmodule Blog.DistCache do
  use Nebulex.Cache, otp_app: :blog
end
```

And the `Blog.LocalCache` module is defined in `lib/blog/local_cache.ex`:

```elixir
defmodule Blog.LocalCache do
  use Nebulex.Cache, otp_app: :blog
end
```

And remember to setup the `Blog.DistCache` and its local cache `Blog.LocalCache`
as supervisors within the application's supervision tree (such as we did it
previously):

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.Cache, []),      # Previous created local cache
    supervisor(Blog.DistCache, []),  # Distributed cache
    supervisor(Blog.LocalCache, [])  # Local cache that will be used by the distributed cache
  ]

  ...
```

Now we are ready to start using our distributed cache!

To learn more about how distributed cache works, please check
`Nebulex.Adapters.Dist` documentation, and also it is recommended see the
[partitioned cache example](https://github.com/cabol/nebulex_examples/tree/master/partitioned_cache)

## Multilevel Cache

Nebulex also provides the adapter `Nebulex.Adapters.Multilevel`, which allows to
setup a multi-level caching hierarchy.

First, let's create a multi-level cache module:

```
mix nebulex.gen.cache -c Blog.MultilevelCache -a Nebulex.Adapters.Multilevel
```

This command will generate the configuration required to use our multilevel
cache. Within the `config/config.exs`:

```elixir
config :blog, Blog.MultilevelCache,
  adapter: Nebulex.Adapters.Multilevel,
  cache_model: :inclusive,
  levels: []
```

Next step is to set the `levels` config value, with the caches that will be part
of the caching hierarchy. Let's suppose we want a two levels cache, L1 and L2
cache, where L1 (first level) is our local cache and L2 (second level) the
distributed cache. Therefore, the configuration would be like so:

```elixir
config :blog, Blog.MultilevelCache,
  adapter: Nebulex.Adapters.Multilevel,
  cache_model: :inclusive,
  levels: [Blog.Cache, Blog.DistCache]
```

Note that the `Blog.LocalCache` cannot be part of the levels, since it is the
cache used by `Blog.DistCache` behind scenes.

And remember to setup the `Blog.MultilevelCache` as a supervisor within the
application's supervision tree (such as we did it previously):

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.Cache, []),          # Previous created local cache
    supervisor(Blog.DistCache, []),      # Distributed cache
    supervisor(Blog.LocalCache, []),     # Local cache that will be used by the distributed cache
    supervisor(Blog.MultilevelCache, []) # Multilevel cache
  ]

  ...
```

Let's try it out!

Insert some date into the distributed cache:

```elixir
iex> Blog.DistCache.set("foo", "bar")
"bar"

iex> Blog.Cache.get("foo")
nil

iex> Blog.DistCache.get("foo")
"bar"
```

Now let's retrieve the data but using the multi-level cache:

```elixir
iex> Blog.MultilevelCache.get("foo")
"bar"

iex> Blog.Cache.get("foo")
"bar"

iex> Blog.DistCache.get("foo")
"bar"
```

As you can see the date is now cached in out local cache `Blog.Cache`, the
multi-level cache did the work.

To learn more about how multilevel-cache works, please check
`Nebulex.Adapters.Multilevel` documentation, and also it is recommended see the
[near cache example](https://github.com/cabol/nebulex_examples/tree/master/near_cache)

## Pre/Post Hooks

See [hooks documentation](http://hexdocs.pm/nebulex/hooks.html).
