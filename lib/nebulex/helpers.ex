defmodule Nebulex.Helpers do
  # Module for general purpose helpers.
  @moduledoc false

  ## API

  @spec get_option(Keyword.t(), atom, (any -> boolean), any, (any -> any) | nil) :: any
  def get_option(opts, key, on_get, default \\ nil, on_false \\ nil) do
    case Keyword.get(opts, key) do
      nil -> default
      val -> (on_get.(val) && val) || on_false(on_false, val, default)
    end
  end

  @spec assert_behaviour(module, module, String.t()) :: module
  def assert_behaviour(module, behaviour, msg \\ "module") do
    if behaviour in module_behaviours(module, msg) do
      module
    else
      raise ArgumentError,
            "expected #{inspect(module)} to implement the behaviour #{inspect(behaviour)}"
    end
  end

  @spec module_behaviours(module, String.t()) :: [module]
  def module_behaviours(module, msg) do
    if Code.ensure_compiled(module) != {:module, module} do
      raise ArgumentError,
            "#{msg} #{inspect(module)} was not compiled, " <>
              "ensure it is correct and it is included as a project dependency"
    end

    for {:behaviour, behaviours} <- module.__info__(:attributes),
        behaviour <- behaviours,
        do: behaviour
  end

  @spec with_meta(atom, (module, Nebulex.Adapter.adapter_meta() -> term)) :: term
  def with_meta(name, fun) do
    {adapter, adapter_meta} = Nebulex.Cache.Registry.lookup(name)
    fun.(adapter, adapter_meta)
  end

  ## Private Functions

  defp on_false(fun, val, _) when is_function(fun, 1), do: fun.(val)
  defp on_false(_, _, default), do: default
end
