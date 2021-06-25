defmodule Nebulex.Caching.SimpleKeyGenerator do
  @moduledoc """
  Default key generator implementation.

  It implementats a simple algorithm:

    * If no params are given, return `0`.
    * If only one param is given, return that param as key.
    * If more than one param is given, return a key computed from the hashes
      of all parameters (`:erlang.phash2(args)`).

  > Based on the [default key generation in Spring Cache Abstraction](https://docs.spring.io/spring-framework/docs/3.2.x/spring-framework-reference/html/cache.html#cache-annotations-cacheable-default-key).

  This implementation aims to cover those simple/generic scenarios where the
  key generated based on the arguments only, fulfill the needs. For example:

      defmodule MyApp.Users do
        use Nebulex.Caching

        alias MayApp.Cache

        @decorate cacheable(cache: Cache)
        def get_user(id) do
          # logic for retrieving a user...
        end

        @decorate cache_evict(cache: Cache)
        def delete_user(id) do
          # logic for deleting a user...
        end
      end

  The key generator will generate the same key for both, cacheable and
  evict functions; since it is generated based on the arguments only.
  """

  @behaviour Nebulex.Caching.KeyGenerator

  @impl true
  def generate(_mod, _fun, []), do: 0
  def generate(_mod, _fun, [arg]), do: arg
  def generate(_mod, _fun, args), do: :erlang.phash2(args)
end
