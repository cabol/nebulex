# Cache Usage Patterns via Nebulex.Caching.Decorators

There are several common access patterns when using a cache. **Nebulex**
supports most of these patterns by means of
[Nebulex.Caching.Decorators][nbx_caching].

[nbx_caching]: http://hexdocs.pm/nebulex/Nebulex.Caching.Decorators.html

> Most of the following documentation about caching patterns it based on
  [EHCache Docs][EHCache]

[EHCache]: https://github.com/ehcache/ehcache3/blob/master/docs/src/docs/asciidoc/user/caching-patterns.adoc

## Cache-aside

With the cache-aside pattern, application code uses the cache directly.

This means that application code which accesses the system-of-record (SoR)
should consult the cache first, and if the cache contains the data, then return
the data directly from the cache, bypassing the SoR. Otherwise, the application
code must fetch the data from the system-of-record, store the data in the cache,
and then return it. When data is written, the cache must be updated along with
the system-of-record.

### Reading values

```elixir
if value = MyCache.get(key) do
  value
else
  value = SoR.get(key) # maybe Ecto?
  :ok = MyCache.put(key, value)
  value
end
```

### Writing values

```elixir
:ok = MyCache.put(key, value)
SoR.insert(key, value) # maybe Ecto?
```

As you may have noticed, this is the default behavior for most of the caches,
we have to interact directly with the cache as well as the SoR (most likely the
Database).

## Cache-as-SoR

The cache-as-SoR pattern implies using the cache as though it were the
primary system-of-record (SoR).

The pattern delegates SoR reading and writing activities to the cache, so that
application code is (at least directly) absolved of this responsibility.
To implement the cache-as-SoR pattern, use a combination of the following
read and write patterns:

 * **Read-through**

 * **Write-through**

Advantages of using the cache-as-SoR pattern are:

 * Less cluttered application code (improved maintainability through centralized
   SoR read/write operations)

 * Choice of write-through or write-behind strategies on a per-cache basis

 * Allows the cache to solve the thundering-herd problem

A disadvantage of using the cache-as-SoR pattern is:

 * Less directly visible code-path

But how to get all this out-of-box? This is where declarative annotation-based
caching comes in. Nebulex provides a set of annotation to abstract most of the
logic behind **Read-through** and **Write-through** patterns and make the
implementation extremely easy. But let's go over these patterns more in detail
and how to implement them by using [Nebulex annotations][nbx_caching].

## Read-through

Under the read-through pattern, the cache is configured with a loader component
that knows how to load data from the system-of-record (SoR).

When the cache is asked for the value associated with a given key and such an
entry does not exist within the cache, the cache invokes the loader to retrieve
the value from the SoR, then caches the value, then returns it to the caller.

The next time the cache is asked for the value for the same key it can be
returned from the cache without using the loader (unless the entry has been
evicted or expired).

This pattern can be easily implemented using `cache` decorator as follows:

```elixir
defmodule MyApp.Example do
  use Nebulex.Caching

  alias MyApp.Cache

  @ttl :timer.hours(1)

  @decorate cacheable(cache: Cache, key: name)
  def get_by_name(name) do
    # your logic (the loader to retrieve the value from the SoR)
  end

  @decorate cacheable(cache: Cache, key: age, opts: [ttl: @ttl])
  def get_by_age(age) do
    # your logic (the loader to retrieve the value from the SoR)
  end

  @decorate cacheable(cache: Cache)
  def all(query) do
    # your logic (the loader to retrieve the value from the SoR)
  end
end
```

As you can see, the loader to retrieve the value from the system-of-record (SoR)
is the function logic itself.

## Write-through

Under the write-through pattern, the cache is configured with a writer component
that knows how to write data to the system-of-record (SoR).

When the cache is asked to store a value for a key, the cache invokes the writer
to store the value in the SoR, as well as updating (or deleting) the cache.

This pattern can be implemented using `defevict` or `defupdatable`. When the
data is written to the system-of-record (SoR), you can update the cached value
associated with the given key using `defupdatable`, or just delete it using
`defevict`.

```elixir
defmodule MyApp.Example do
  use Nebulex.Caching

  alias MyApp.Cache

  # When the data is written to the SoR, it is updated in the cache
  @decorate cache_put(cache: Cache, key: something)
  def update(something) do
    # Write data to the SoR (most likely the Database)
  end

  # When the data is written to the SoR, it is deleted (evicted) from the cache
  @decorate cache_evict(cache: Cache, key: something)
  def update_something(something) do
    # Write data to the SoR (most likely the Database)
  end
end
```

As you can see, the logic to write data to the system-of-record (SoR) is the
function logic itself.
