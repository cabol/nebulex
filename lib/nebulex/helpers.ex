defmodule Nebulex.Helpers do
  # Module for general purpose helpers.
  @moduledoc false

  ## API

  @spec get_option(Keyword.t(), atom, String.t(), (any -> boolean), term) :: term
  def get_option(opts, key, expected, valid?, default \\ nil)
      when is_list(opts) and is_atom(key) do
    value = Keyword.get(opts, key, default)

    if valid?.(value) do
      value
    else
      raise ArgumentError, "expected #{key}: to be #{expected}, got: #{inspect(value)}"
    end
  end

  @spec get_boolean_option(Keyword.t(), atom, boolean) :: term
  def get_boolean_option(opts, key, default \\ false)
      when is_list(opts) and is_atom(key) and is_boolean(default) do
    value = Keyword.get(opts, key, default)

    if is_boolean(value) do
      value
    else
      raise ArgumentError, "expected #{key}: to be boolean, got: #{inspect(value)}"
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
