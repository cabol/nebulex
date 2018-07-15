
defmodule Nebulex.ConflictError do
  @moduledoc """
  Raised at runtime when there is a version mismatch between the
  cached object and the requested version.
  """
  defexception [:message, :cached, :version]

  @doc false
  def exception(opts) do
    version = Keyword.fetch!(opts, :version)
    cached = Keyword.fetch!(opts, :cached)

    msg = """
    Version conflict error.

    Cached object

    #{inspect cached}

    Requested version

    #{inspect version}
    """

    %__MODULE__{message: msg, cached: cached.version, version: version}
  end
end
