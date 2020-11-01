defmodule Nebulex.Adapters.Local.Backend.ETS do
  @moduledoc false
  use Nebulex.Adapters.Local.Backend

  ## API

  @doc false
  def child_spec(opts) do
    opts
    |> parse_opts()
    |> generation_spec()
    |> List.wrap()
    |> sup_spec()
  end

  @doc false
  def new(_meta_tab, tab_opts) do
    :ets.new(__MODULE__, tab_opts)
  end

  @doc false
  def delete(_meta_tab, gen_tab) do
    :ets.delete(gen_tab)
  end
end
