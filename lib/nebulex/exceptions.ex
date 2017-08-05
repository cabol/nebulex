
defmodule Nebulex.VersionConflictError do
  @moduledoc """
  Raised at runtime when there is a version mismatch between the
  cached object and the requested version.
  """
  defexception [:message, :cached_vsn, :requested_vsn]

  @doc false
  def exception(opts) do
    action = Keyword.fetch!(opts, :action)
    version = Keyword.fetch!(opts, :version)
    cached = Keyword.fetch!(opts, :cached)

    msg = """
    could not perform #{inspect action} because versions mismatch.

    Cached version

    #{inspect cached.version}

    Requested version

    #{inspect version}
    """

    %__MODULE__{message: msg, cached_vsn: cached.version, requested_vsn: version}
  end
end
