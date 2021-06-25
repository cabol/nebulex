defmodule Nebulex.Caching.KeyGenerator do
  @moduledoc """
  Cache key generator. Used for creating a key based on the given module,
  function name and its arguments (the module and function name are used
  as context).

  See the default implementation `Nebulex.Caching.SimpleKeyGenerator`.
  """

  @typedoc "KeyGenerator"
  @type t :: module

  @doc """
  Generates a key for the given `module`, `function_name`, and its `args`.
  """
  @callback generate(module, function_name :: atom, args :: [term]) :: term
end
