defmodule Nebulex.Helpers do
  # Module for general purpose helpers.
  @moduledoc false

  ## API

  @spec get_option(Keyword.t(), atom, binary, (any -> boolean), term) :: term
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

  @spec assert_behaviour(module, module, binary) :: module
  def assert_behaviour(module, behaviour, msg \\ "module") do
    if behaviour in module_behaviours(module, msg) do
      module
    else
      raise ArgumentError,
            "expected #{inspect(module)} to implement the behaviour #{inspect(behaviour)}"
    end
  end

  @spec module_behaviours(module, binary) :: [module]
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

  @doc false
  defmacro unwrap_or_raise(call) do
    quote do
      case unquote(call) do
        {:ok, value} -> value
        {:error, reason} when is_exception(reason) -> raise reason
        {:error, reason} -> raise Nebulex.Error, reason: reason
        other -> other
      end
    end
  end

  @doc false
  defmacro wrap_ok(call) do
    quote do
      {:ok, unquote(call)}
    end
  end

  @doc false
  defmacro wrap_error(call) do
    quote do
      {:error, unquote(call)}
    end
  end

  @doc false
  defmacro wrap_error(exception, opts) do
    quote do
      {:error, unquote(exception).exception(unquote(opts))}
    end
  end
end
