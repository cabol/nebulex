
defmodule Nebulex.VersionConflictError do
  @moduledoc """
  Raised at runtime when there is a version mismatch between the
  cached object and the requested version.
  """
  defexception [:message, :cached, :version]

  @doc false
  def exception(opts) do
    action = Keyword.fetch!(opts, :action)
    cached = Keyword.fetch!(opts, :cached)
    version = Keyword.fetch!(opts, :version)

    msg = """
    could not perform #{inspect action} because versions mismatch.

    Requested version

    #{inspect version}

    Cached Object

    #{inspect cached}
    """

    %__MODULE__{message: msg, cached: cached, version: version}
  end
end

defmodule Nebulex.RemoteProcedureCallError do
  @moduledoc """
  Raised at runtime when a RPC error occurs and forwards the remote
  original exception.
  """
  defexception [:message]

  @doc false
  def exception(opts) do
    {:EXIT, {remote_exception, _}} = Keyword.fetch!(opts, :exception)
    remote_exception
  end
end
