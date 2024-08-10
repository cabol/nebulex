defmodule Nebulex.Cache.Info do
  @moduledoc false

  import Nebulex.Adapter, only: [defcommandp: 2]
  import Nebulex.Utils, only: [unwrap_or_raise: 1]

  ## API

  @doc """
  Implementation for `c:Nebulex.Cache.info/2`.
  """
  def info(name, spec, opts) when is_atom(spec) or is_list(spec) do
    do_info(name, spec, opts)
  end

  @compile {:inline, do_info: 3}
  defcommandp do_info(name, spec, opts), command: :info

  @doc """
  Implementation for `c:Nebulex.Cache.info!/2`.
  """
  def info!(name, item, opts) do
    unwrap_or_raise info(name, item, opts)
  end
end
