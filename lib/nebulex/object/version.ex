defmodule Nebulex.Object.Version do
  @moduledoc """
  Version generator for cached objects.

  The purpose of this module is to allow users implement custom
  version generators. This interface is used by the adapters to
  generate new object versions.

  ## Example

      defmodule MyApp.Timestamp do
        @behaviour Nebulex.Object.Version

        def generate(_) do
          DateTime.utc_now |> DateTime.to_unix(:nanoseconds)
        end
      end

  If you are going to rely on this feature, it is recommended to use a good
  version generation algorithm (e.g.:  **Vector Clocks**).
  """

  @doc """
  Returns a cache object with the new generated version.
  """
  @callback generate(object :: Nebulex.Object.t()) :: Nebulex.Object.t()

  @typedoc "On-Conflict options"
  @type on_conflict :: :raise | :override | :nothing

  @typedoc "Validation result"
  @type result :: {on_conflict, Nebulex.Object.t()} | no_return

  alias Nebulex.Object

  @doc """
  Validates version conflicts for cached objects.

  This function should be reused by cache's adapters which implement
  optimistic locking through a version property on cached objects.

  ## Example

  From your cache's adapter:

      def get(cache, key, opts) do
        # your code ...

        case Version.validate(cached_object, opts) do
          {:override, obj} ->
            # your code ...

          {:nothing, obj} ->
            # your code ...
        end
      end

  For more information, you can check the different adapter implementations.
  """
  @spec validate(Nebulex.Object.t(), Nebulex.Cache.opts) :: result
  def validate(nil, _opts) do
    {:override, nil}
  end

  def validate(cached, opts) do
    version = Keyword.get(opts, :version)
    on_conflict = Keyword.get(opts, :on_conflict, :raise)
    on_conflict(cached, version, on_conflict)
  end

  ## Helpers

  defp on_conflict(cached, nil, _on_conflict),
    do: {:override, cached}

  defp on_conflict(%Object{version: version} = cached, version, _on_conflict),
    do: {:override, cached}

  defp on_conflict(cached, _version, on_conflict) when on_conflict in [:override, :nothing],
    do: {on_conflict, cached}

  defp on_conflict(cached, version, :raise),
    do: raise Nebulex.ConflictError, cached: cached, version: version

  defp on_conflict(_, _, other),
    do: raise ArgumentError, "unknown value for :on_conflict, got: #{inspect other}"
end
