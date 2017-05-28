# Getting Started

This guide is an introduction to [Nebulex](https://github.com/cabol/nebulex),
a local and distributed caching tool for Elixir. Nebulex design and API are
based on [Ecto](https://github.com/elixir-ecto/ecto), taking advantage of its
flexible and pluggable architecture. In the same way as Ecto, developers can
provide their own Cache implementations.

In this guide, we're going to learn some basics about Nebulex, such as setting,
retrieving and destroying cache entries (key/value pairs).

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
  [{:nebulex, "~> 1.0"}]
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

To fetch all entries from cache, Nebulex provides the `all` function:

```elixir
Blog.Cache.all
```

By default, it returns all keys, but gain, you can request to return either the
key, value or object.

```elixir
Blog.Cache.all(return: :value)

Blog.Cache.all(return: :object)
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
