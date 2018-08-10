defmodule Nebulex.VersionConflictError do
  @moduledoc """
  Raised at runtime when there is a version conflict between the required
  object version and the cached object version.
  """
  defexception [:cached, :version]

  @impl true
  def message(%{cached: cached, version: version}) do
    """
    could not perform cache action because versions mismatch.

    Requested version

    #{pretty(version)}

    Cached object

    #{pretty(cached)}
    """
  end

  defp pretty(term) do
    term
    |> inspect(pretty: true)
    |> String.split("\n")
    |> Enum.map_join("\n", &("    " <> &1))
  end
end

defmodule Nebulex.KeyAlreadyExistsError do
  @moduledoc """
  Raised at runtime when a key already exists in cache.
  """
  defexception [:key, :cache]

  @impl true
  def message(%{key: key, cache: cache}) do
    "key #{inspect(key)} already exists in cache #{inspect(cache)}"
  end
end
