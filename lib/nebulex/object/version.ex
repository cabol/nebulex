defmodule Nebulex.Object.Version do
  @moduledoc """
  Version handler for cached objects.

  The purpose of this module is to allow users implement custom
  version generator and validator. This interface is used by the
  adapters to generate and/or validate object versions.

  ## Example

      defmodule MyApp.Versioner do
        @behaviour Nebulex.Object.Version

        def generate(nil), do: 0

        def generate(%Object{version: version} = object) do
          %{object | version: version + 1}
        end
      end

  If you are going to rely on this feature, it is recommended to use a good
  version generation algorithm (e.g.:  **Vector Clocks**).
  """

  @doc """
  Returns a cache object with the new generated version.
  """
  @callback generate(cached_object :: Nebulex.Object.t()) :: Nebulex.Object.t()

  alias Nebulex.Object

  @doc """
  Validates version conflicts for the given cached `object_or_key`.

  This function is used by cache's adapters which implement
  optimistic locking via object's version.

  For more information, check the different adapter implementations.
  """
  @spec validate!(
          object_or_key :: object | Nebulex.Cache.key(),
          cache :: Nebulex.Cache.t(),
          opts :: Nebulex.Cache.opts()
        ) :: {:override | :nothing, object | nil} | no_return
        when object: Nebulex.Object.t()
  def validate!(nil, _cache, _opts), do: {:override, nil}

  def validate!(%Object{} = object, cache, opts) do
    opts
    |> Keyword.get(:version)
    |> case do
      nil ->
        {:override, object}

      vsn ->
        # TODO: There is still a race condition between the `get` to retrieve
        # the cached object and the command executed later in the adapter
        cache
        |> maybe_get(object)
        |> on_conflict(vsn, Keyword.get(opts, :on_conflict, :raise))
    end
  end

  def validate!(key, cache, opts) do
    validate!(%Object{key: key}, cache, opts)
  end

  ## Helpers

  defp maybe_get(cache, %Object{key: key, value: nil}),
    do: cache.__adapter__.get(cache, key, [])

  defp maybe_get(_cache, %Object{} = object),
    do: object

  defp on_conflict(%Object{version: version} = cached, version, _on_conflict),
    do: {:override, cached}

  defp on_conflict(cached, _version, on_conflict) when on_conflict in [:override, :nothing],
    do: {on_conflict, cached}

  defp on_conflict(cached, version, :raise),
    do: raise(Nebulex.VersionConflictError, cached: cached, version: version)

  defp on_conflict(_, _, other),
    do: raise(ArgumentError, "unknown value for :on_conflict, got: #{inspect(other)}")
end
