# Getting Started

This guide is an introduction to [Nebulex](https://github.com/cabol/nebulex),
a local and distributed caching library for Elixir. Nebulex API is pretty much
inspired by [Ecto](https://github.com/elixir-ecto/ecto), taking advantage of
its simplicity, flexibility and pluggable architecture. In the same way
as Ecto, developers can provide their own cache (adapter) implementations.

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
  [
    {:nebulex, "~> 1.1"}
  ]
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
  gc_interval: 86_400 # 24 hrs
```

The `Blog.Cache` module is defined in `lib/blog/cache.ex` by our
`mix nebulex.gen.cache` command:

```elixir
defmodule Blog.Cache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Local
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

`Elixir < 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.Cache, []),
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
user = %{id: 1, username: "cabol", email: "cabol@email.com"}

Blog.Cache.set(user[:id], user)
```

To insert the data into our cache, we call `set` on `Blog.Cache`. This function
tells Nebulex that we want to insert a new key/value entry into the cache
corresponding `Blog.Cache`.

A successful set will return (by default) the inserted value, like so:

```elixir
%{id: 1, username: "cabol", email: "cabol@email.com"}
```

But, using the option `:return` we can ask for return either the value, key or
the entire `Nebulex.Object`, like so:

```elixir
Blog.Cache.set("foo", "bar", return: :key)

Blog.Cache.set("foo", "bar", return: :object)

Blog.Cache.set("foo", "bar", return: :value) # Default
```

### Add and Replace

As we saw previously, `set` creates a new entry in cache if it doesn't exist,
or overrides it if it does exist (including the `:ttl`). However, there might
be circumstances where we want to set the entry only if it doesn't exit or the
other way around, this is where `add`, `add!`, `replace` and `replace!`
functions come in.

Let's try `add` and `add!` functions:

```elixir
{:ok, "value"} = Blog.Cache.add("new", "value")

"value" = Blog.Cache.add!("new2", "value")

# returns `:error` because the `key` already exists
:error = Blog.Cache.add("new", "value")

# same as previous one but raises `Nebulex.KeyAlreadyExistsError`
Blog.Cache.add!("new", "new value")
```

Now `replace` and `replace!` functions:

```elixir
{:ok, "new value"} = Blog.Cache.replace("new", "new value")

"new value" = Blog.Cache.replace!("new2", "new value")

# returns `:error` because the `key` doesn't exist
:error = Blog.Cache.replace("another", "new value")

# same as previous one but raises `KeyError`
Blog.Cache.replace!("another", "new value")

# update only the TTL without alter the current value (value is set to nil)
Blog.Cache.replace!("existing key", nil, ttl: 60)

# updating both, value and TTL
Blog.Cache.replace!("existing key", "value", ttl: 60)
```

## Retrieving entries

First, let's create some data as we learned before.

```elixir
users = [
  %{id: 1, first_name: "Galileo", last_name: "Galilei"},
  %{id: 2, first_name: "Charles", last_name: "Darwin"},
  %{id: 3, first_name: "Albert", last_name: "Einstein"}
]

Enum.each(users, fn(user) -> Blog.Cache.set(user[:id], user) end)
```

This code will create three new users in our cache.

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
Blog.Cache.has_key?(1)
```

It returns `true` if the ket exist and `false` otherwise.

### Fetch and/or stream multiple entires

Nebulex provides functions to fetch or stream all entries from cache matching
the given query.

To fetch all entries from cache:

```elixir
# by default, returns all keys
Blog.Cache.all()

# fetch all entries and return values
Blog.Cache.all(nil, return: :value)

# fetch all entries and return objects
Blog.Cache.all(nil, return: :object)

# built-in queries in `Nebulex.Adapters.Local` adapter
Blog.Cache.all(nil)
Blog.Cache.all(:all_unexpired)
Blog.Cache.all(:all_expired)

# if we are using `Nebulex.Adapters.Local` adapter, the stored entry
# is a tuple `{key, value, version, expire_at}`, then the match spec
# could be something like:
spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
Blog.Cache.all(spec)

# using Ex2ms
import Ex2ms

spec =
  fun do
    {key, value, _, _} when value > 10 -> {key, value}
  end

Blog.Cache.all(spec)
```

In the same way, we can stream all entries:

```elixir
Blog.Cache.stream()

Blog.Cache.stream(nil, page_size: 3, return: :value)

Blog.Cache.stream(nil, page_size: 3, return: :object)

# using `Nebulex.Adapters.Local` adapter
spec = [{{:"$1", :"$2", :_, :_}, [{:>, :"$2", 10}], [{{:"$1", :"$2"}}]}]
Blog.Cache.stream(spec, page_size: 3)

# using Ex2ms
import Ex2ms

spec =
  fun do
    {key, value, _, _} when value > 10 -> {key, value}
  end

Blog.Cache.stream(spec, page_size: 3)
```

## Updating entries

If you want to generate the new entry based on the current one, you can use
`get` and then `set`, if you don't care about the current cached value, you
can use only `set` (or `replace`), like so:

```elixir
v1 = Blog.Cache.get(1)

Blog.Cache.set(1, %{v1 | first_name: "Nebulex"})

# In case you don't care about an existing entry, you can just override the
# existing one (if it exists); remember, `set` is an idempotent operation
Blog.Cache.set(1, "anything")
```

However, Nebulex provides `update` and `get_and_update` functions to update an
entry value based on current one, for example:

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
objects. Now let's see how to delete an object using Nebulex; the basic and/or
main way to do so is through `delete/2` function.

```elixir
Blog.Cache.delete(1)
```

By default, `delete` returns the `key` either if success or not, however, it is
possible also to pass the `:return` option.

### Take

There is another way to delete an entry and at the same time to retrieve it,
the function to achieve this is `take` or `take!`, this is an example:

```elixir
Blog.Cache.take(1)

Blog.Cache.take(2, return: :key)

Blog.Cache.take!(3, return: :object)

# returns `nil` if `key` doesn't exist
nil = Blog.Cache.take("nonexistent")

# same as previous one but raises `KeyError`
Blog.Cache.take!("nonexistent")
```

Similar to `set` and `get`, `take` returns the value by default, but you can
request to return either the key, value or object.

### Flush

Nebulex also provides a function to flush all cache entries, like so:

```elixir
Blog.Cache.flush()
```

## Info

The last thing we’ll cover in this guide is how to retrieve information about
cached objects or the cache itself.

### Object Info

To retrieve the TTL of an object:

```elixir
Blog.Cache.object_info("mykey", :ttl)
```

And if we want to retrieve the version:

```elixir
Blog.Cache.object_info("mykey", :version)
```

### Cache Info

To get the total number of cached objects:

```elixir
Blog.Cache.size()
```

## Distributed Cache

Nebulex provides the adapter `Nebulex.Adapters.Dist`, which allows to setup a
partitioned cache topology.

Let's setup our distributed cache by running this command:

```
mix nebulex.gen.cache -c Blog.DistCache -a Nebulex.Adapters.Dist
```

This command will generate the configuration required to use our distributed
cache; it is defined in `config/config.exs`:

```elixir
config :blog, Blog.DistCache,
  local: :YOUR_LOCAL_CACHE,
  node_selector: Nebulex.Adapters.Dist
```

Replace the `local` config value `:YOUR_LOCAL_CACHE` by an existing local cache
(e.g.: we can set the local cache we created previously), or create a new
one (we will create a new one within `Blog.DistCache`).

The `Blog.DistCache` module is defined in `lib/blog/dist_cache.ex` by our
`mix nebulex.gen.cache` command:

```elixir
defmodule Blog.DistCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Dist
end
```

As mentioned previously, let's add the local backend (local cache):

```elixir
defmodule Blog.DistCache do
  use Nebulex.Cache,
    otp_app: :blog,
    adapter: Nebulex.Adapters.Dist

  defmodule Primary do
    use Nebulex.Cache,
      otp_app: :blog,
      adapter: Nebulex.Adapters.Local
  end
end
```

Now we have to add the new local cache to the config, and also replace the
`local` config value `:YOUR_LOCAL_CACHE` by our new local cache in the
distributed cache config.

```elixir
# Local backend for the distributed cache
config :blog, Blog.DistCache.Primary,
  gc_interval: 86_400 # 24 hrs

# Distributed Cache
config :blog, Blog.DistCache,
  local: Blog.DistCache.Primary,
  node_selector: Nebulex.Adapters.Dist
```

And remember to setup the `Blog.DistCache` and its local backend
`Blog.DistCache.Primary` as supervisors within the application's
supervision tree (such as we did it previously):

`Elixir < 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.Cache, []),            # Previous created local cache
    supervisor(Blog.DistCache, []),        # Distributed cache
    supervisor(Blog.DistCache.Primary, []) # Local cache that will be used by the distributed cache
  ]

  ...
```

`Elixir >= 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    Blog.Cache,            # Previous created local cache
    Blog.DistCache,        # Distributed cache
    Blog.DistCache.Primary # Local cache that will be used by the distributed cache
  ]

  ...
```

Now we are ready to start using our distributed cache!

### Timeout option

The `Nebulex.Adapters.Dist` supports `:timeout` option, it is a value in
milliseconds for the command that will be executed.

```elixir
Blog.DistCache.get("foo", timeout: 10)

# if the timeout is exceeded, then the current process will exit
Blog.DistCache.set("foo", "bar", timeout: 10)
# ** (EXIT) time out
```

To learn more about how distributed cache works, please check
`Nebulex.Adapters.Dist` documentation, and also it is recommended see the
[partitioned cache example](https://github.com/cabol/nebulex_examples/tree/master/partitioned_cache)

## Multilevel Cache

Nebulex also provides the adapter `Nebulex.Adapters.Multilevel`, which allows to
setup a multi-level caching hierarchy.

First, let's create a multi-level cache module:

```
mix nebulex.gen.cache -c Blog.Multilevel -a Nebulex.Adapters.Multilevel
```

This command will generate the configuration required to use our multilevel
cache; it is defined in `config/config.exs`:

```elixir
config :blog, Blog.Multilevel,
  cache_model: :inclusive,
  levels: []
```

Next step is to set the `levels` config value, with the caches that will be part
of the caching hierarchy. Let's suppose we want a two levels cache, L1 and L2
cache, where L1 (first level) is our local cache and L2 (second level) the
distributed cache. Therefore, the configuration would be like so:

```elixir
config :blog, Blog.Multilevel,
  cache_model: :inclusive,
  levels: [Blog.Cache, Blog.DistCache]
```

Note that the `Blog.DistCache.Primary` cannot be part of the levels, since it
is the backend used by `Blog.DistCache` behind scenes.

And remember to setup the `Blog.Multilevel` as a supervisor within the
application's supervision tree (such as we did it previously):

`Elixir < 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    supervisor(Blog.Cache, []),             # Previous created local cache
    supervisor(Blog.DistCache, []),         # Distributed cache
    supervisor(Blog.DistCache.Primary, []), # Local cache that will be used by the distributed cache
    supervisor(Blog.MultilevelCache, [])    # Multilevel cache
  ]

  ...
```

`Elixir >= 1.5.0`:

```elixir
def start(_type, _args) do
  import Supervisor.Spec, warn: false

  children = [
    Blog.Cache,             # Previous created local cache
    Blog.DistCache,         # Distributed cache
    Blog.DistCache.Primary, # Local cache that will be used by the distributed cache
    Blog.Multilevel         # Multilevel cache
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
iex> Blog.Multilevel.get("foo")
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

## Other important guides

 * [Nebulex.Caching DSL](http://hexdocs.pm/nebulex/caching-dsl.html)  - Tailored
   DSL to implement different cache usage patterns.

 * [Pre and Post Hooks](http://hexdocs.pm/nebulex/hooks.html) - Ability
   to hook any function call for a cache and add custom logic before and/or
   after function execution.
