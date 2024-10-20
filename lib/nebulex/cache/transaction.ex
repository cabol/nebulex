defmodule Nebulex.Cache.Transaction do
  @moduledoc false

  import Nebulex.Adapter, only: [defcommand: 1, defcommandp: 2]

  @doc """
  Implementation for `c:Nebulex.Cache.transaction/2`.
  """
  def transaction(name, fun, opts) when is_function(fun, 0) do
    do_transaction(name, fun, opts)
  end

  @compile {:inline, do_transaction: 3}
  defcommandp do_transaction(name, fun, opts), command: :transaction

  @doc """
  Implementation for `c:Nebulex.Cache.in_transaction?/1`.
  """
  defcommand in_transaction?(name, opts)
end
