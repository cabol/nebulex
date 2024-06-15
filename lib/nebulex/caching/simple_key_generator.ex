defmodule Nebulex.Caching.SimpleKeyGenerator do
  @moduledoc """
  Default key generator implementation.

  It implementats a simple algorithm:

    * If no arguments are given, return `0`.
    * If only one argument is given, return that param as key.
    * If more than one argument is given, return a key computed
      from the hash of all arguments (`:erlang.phash2(args)`).

  This approach works well for those cases where the decorated functions keep
  the same arguments (same hash code). For example:

      defmodule MyApp.Users do
        use Nebulex.Caching, cache: MayApp.Cache

        @decorate cacheable()
        def get_user(id) do
          # logic for retrieving a user...
        end

        @decorate cache_evict()
        def delete_user(id) do
          # logic for deleting a user...
        end
      end

  The previous example works because the hash code of the arguments in both
  decorated functions will be the same.
  """

  @behaviour Nebulex.Caching.KeyGenerator

  @impl true
  def generate(context)

  def generate(%{args: []}), do: 0
  def generate(%{args: [arg]}), do: arg
  def generate(%{args: args}), do: :erlang.phash2(args)
end
