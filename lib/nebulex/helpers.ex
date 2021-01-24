defmodule Nebulex.Helpers do
  # Module for general purpose helpers.
  @moduledoc false

  ## API

  @spec get_option(Keyword.t(), atom, String.t(), (any -> boolean), term) :: term
  def get_option(opts, key, expected, valid?, default \\ nil) do
    value = Keyword.get(opts, key, default)

    if valid?.(value) do
      value
    else
      raise ArgumentError, "expected #{key}: to be #{expected}, got: #{inspect(value)}"
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

  @spec normalize_module_name([atom | binary | number]) :: module
  def normalize_module_name(list) when is_list(list) do
    list
    |> Enum.map(&Macro.camelize("#{&1}"))
    |> Module.concat()
  end
end
