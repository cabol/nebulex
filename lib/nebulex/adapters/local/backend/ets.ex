defmodule Nebulex.Adapters.Local.Backend.ETS do
  @moduledoc false
  use Nebulex.Adapters.Local.Backend

  ## API

  @doc false
  def child_spec(name, opts) do
    sup_spec(name, [generation_spec(name, parse_opts(opts))])
  end

  @doc false
  def new(name, tab_opts) do
    :ets.new(name, tab_opts)
  end

  @doc false
  def delete(_name, tab) do
    :ets.delete(tab)
  end
end
