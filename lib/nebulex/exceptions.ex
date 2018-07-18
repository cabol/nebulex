
defmodule Nebulex.ConflictError do
  defexception [:cached, :version]

  @impl true
  def message(%{cached: cached, version: version}) do
    """
    could not perform cache action because versions mismatch.

    Requested version

    #{pretty version}

    Cached version

    #{pretty cached.version}

    Cached object

    #{pretty cached}
    """
  end

  defp pretty(term) do
    term
    |> inspect(pretty: true)
    |> String.split("\n")
    |> Enum.map_join("\n", &"    " <> &1)
  end
end

defmodule Nebulex.RPCError do
  defexception [:reason]

  @impl true
  def message(%{reason: reason}) do
    """
    the remote procedure call failed with reason:

    #{inspect reason, pretty: true}
    """
  end
end
