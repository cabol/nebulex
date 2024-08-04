defmodule Nebulex.Utils do
  @moduledoc """
  General purpose utilities.
  """

  # Nebulex exceptions
  @nbx_exception [
    Nebulex.Error,
    Nebulex.KeyError,
    Nebulex.QueryError
  ]

  ## Guards

  @doc """
  Convenience guard to determine whether the given argument `e` is a Nebulex
  exception or not.

  ## Example

      iex> import Nebulex.Utils, only: [is_nebulex_exception: 1]
      iex> is_nebulex_exception(%Nebulex.Error{reason: :error})
      true
      iex> is_nebulex_exception(%{})
      false

  """
  defguard is_nebulex_exception(e)
           when is_exception(e) and :erlang.map_get(:__struct__, e) in @nbx_exception

  @doc """
  Custom guard to validate whether the given `value` is a timeout.

  ## Examples

      iex> import Nebulex.Utils, only: [is_timeout: 1]
      iex> is_timeout(1)
      true
      iex> is_timeout(:infinity)
      true
      iex> is_timeout(-1)
      false
      iex> is_timeout(1.0)
      false
      iex> is_timeout("")
      false
      iex> is_timeout(nil)
      false

  """
  defguard is_timeout(value) when (is_integer(value) and value >= 0) or value == :infinity

  ## Macros

  @doc """
  Convenience macro for unwrapping a function call result and deciding whether
  to raise an exception or return the unwrapped value.

  ## Example

      iex> import Nebulex.Utils
      iex> unwrap_or_raise {:ok, "ok"}
      "ok"
      iex> unwrap_or_raise {:error, %Nebulex.Error{reason: :error}}
      ** (Nebulex.Error) command failed with reason: :error
      iex> unwrap_or_raise :other
      :other

  """
  defmacro unwrap_or_raise(call) do
    quote do
      unquote(call)
      |> unquote(__MODULE__).do_unwrap_or_raise()
    end
  end

  @doc """
  Convenience macro for wrapping the given `call` result into a tuple in the
  shape of `{:ok, result}`.

  ## Example

      iex> import Nebulex.Utils
      iex> wrap_ok "hello"
      {:ok, "hello"}

  """
  defmacro wrap_ok(call) do
    quote do
      {:ok, unquote(call)}
    end
  end

  @doc """
  Convenience macro for wrapping the given `exception` into a tuple in the
  shape of `{:error, exception}`.

  ## Example

      iex> import Nebulex.Utils
      iex> wrap_error Nebulex.Error, reason: :error
      {:error, %Nebulex.Error{reason: :error}}

  """
  defmacro wrap_error(exception, opts) do
    quote do
      {:error, unquote(exception).exception(unquote(opts))}
    end
  end

  ## Utility functions

  @doc """
  A wrapper for `Keyword.get/3` but validates the returned value invoking
  the function `valid?`.

  Raises an `ArgumentError` in case the validation fails.

  ## Examples

      iex> Nebulex.Utils.get_option(
      ...>   [keys: [1, 2, 3]],
      ...>   :keys,
      ...>   "a list with at least one element",
      ...>   &((is_list(&1) and length(&1) > 0) or is_nil(&1))
      ...> )
      [1, 2, 3]

      iex> Nebulex.Utils.get_option(
      ...>   [],
      ...>   :keys,
      ...>   "a list with at least one element",
      ...>   &((is_list(&1) and length(&1) > 0) or is_nil(&1))
      ...> )
      nil

      iex> Nebulex.Utils.get_option(
      ...>   [keys: 123],
      ...>   :keys,
      ...>   "a list with at least one element",
      ...>   &((is_list(&1) and length(&1) > 0) or is_nil(&1))
      ...> )
      ** (ArgumentError) expected keys: to be a list with at least one element, got: 123

  """
  @spec get_option(keyword(), atom(), binary(), (any() -> boolean()), any()) :: any()
  def get_option(opts, key, expected, valid?, default \\ nil)
      when is_list(opts) and is_atom(key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        if valid?.(value) do
          value
        else
          raise ArgumentError, "expected #{key}: to be #{expected}, got: #{inspect(value)}"
        end

      :error ->
        default
    end
  end

  @doc """
  Returns the implemented behaviours for the given `module`.
  """
  @spec module_behaviours(module()) :: [module()]
  def module_behaviours(module) do
    for {:behaviour, behaviours} <- module.__info__(:attributes), behaviour <- behaviours do
      behaviour
    end
  end

  @doc """
  Concatenates a list of "camelized" aliases and returns a new alias.

  It handles binaries, atoms, and numbers.

  ## Examples

      iex> Nebulex.Utils.camelize_and_concat([Foo, :bar])
      Foo.Bar

      iex> Nebulex.Utils.camelize_and_concat([Foo, "bar"])
      Foo.Bar

      iex> Nebulex.Utils.camelize_and_concat([Foo, "Bar", 1])
      :"Elixir.Foo.Bar.1"

  """
  @spec camelize_and_concat([atom() | binary() | number()]) :: atom()
  def camelize_and_concat(list) when is_list(list) do
    list
    |> Enum.map(&Macro.camelize("#{&1}"))
    |> Module.concat()
  end

  @doc """
  Helper function for unwrapping a function result and deciding whether
  to raise an exception or return the unwrapped value.

  ## Examples

      iex> Nebulex.Utils.do_unwrap_or_raise({:ok, "ok"})
      "ok"

      iex> Nebulex.Utils.do_unwrap_or_raise(
      ...>   {:error, %Nebulex.Error{reason: :error}}
      ...> )
      ** (Nebulex.Error) command failed with reason: :error

      iex> Nebulex.Utils.do_unwrap_or_raise({:error, :error})
      ** (Nebulex.Error) command failed with reason: :error

      iex> Nebulex.Utils.do_unwrap_or_raise(:other)
      :other

  """
  def do_unwrap_or_raise(result)

  def do_unwrap_or_raise({:ok, value}) do
    value
  end

  def do_unwrap_or_raise({:error, reason}) when is_nebulex_exception(reason) do
    raise reason
  end

  def do_unwrap_or_raise({:error, reason}) do
    raise Nebulex.Error, reason: reason
  end

  def do_unwrap_or_raise(other) do
    other
  end
end
