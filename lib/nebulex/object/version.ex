defmodule Nebulex.Object.Version do
  @moduledoc ~S"""
  Version handler for cached objects.

  The purpose of this module is to allow users implement custom
  version generator and validator. This interface is used by the
  adapters to generate and/or validate object versions.

  ## Example

      defmodule MyApp.Versioner do
        @behaviour Nebulex.Object.Version

        def generate(nil), do: 0

        def generate(%Object{version: version}) do
          version + 1
        end
      end

  If you are going to rely on this feature, it is recommended to use a good
  version generation algorithm (e.g.:  **Vector Clocks**).
  """

  @doc """
  Generates a new version for the current cached object.
  """
  @callback generate(cached_object :: Nebulex.Object.t()) :: any

  alias Nebulex.Object

  @doc """
  Validates version conflicts for the given cached `object_or_key`.

  This function is used by cache's adapters which implement
  optimistic locking via object's version.

  For more information, check out adapters' implementation.
  """
  @spec validate(
          object_or_key :: object | Nebulex.Cache.key(),
          cache :: Nebulex.Cache.t(),
          opts :: Nebulex.Cache.opts()
        ) :: {:override | :nothing, object | nil}
        when object: Nebulex.Object.t()
  def validate(nil, _cache, _opts), do: {:override, nil}

  def validate(object_or_key, cache, opts) do
    opts
    |> Keyword.get(:version)
    |> validate(object_or_key, cache, opts)
  end

  ## Helpers

  defp validate(nil, %Object{} = object, _cache, _opts) do
    {:override, object}
  end

  defp validate(nil, key, _cache, _opts) do
    {:override, %Object{key: key}}
  end

  defp validate(vsn, object_or_key, cache, opts) do
    cache
    |> maybe_get(object_or_key)
    |> on_conflict(vsn, Keyword.get(opts, :on_conflict, :raise))
  end

  defp maybe_get(_cache, %Object{} = object),
    do: object

  defp maybe_get(cache, key),
    do: cache.__adapter__.get(cache, key, [])

  defp on_conflict(%Object{version: version} = cached, version, _on_conflict),
    do: {:override, cached}

  defp on_conflict(cached, _version, on_conflict) when on_conflict in [:override, :nothing],
    do: {on_conflict, cached}

  defp on_conflict(cached, version, :raise),
    do: raise(Nebulex.VersionConflictError, cached: cached, version: version)

  defp on_conflict(_, _, other),
    do: raise(ArgumentError, "unknown value for :on_conflict, got: #{inspect(other)}")
end
