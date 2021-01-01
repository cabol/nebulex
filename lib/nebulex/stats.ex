defmodule Nebulex.Stats do
  @moduledoc """
  Basic cache stats.
  """

  # Stats data type
  defstruct hits: 0,
            misses: 0,
            writes: 0,
            evictions: 0,
            expirations: 0

  @typedoc "Nebulex.Stats fields"
  @type t :: %__MODULE__{
          hits: non_neg_integer,
          misses: non_neg_integer,
          writes: non_neg_integer,
          evictions: non_neg_integer,
          expirations: non_neg_integer
        }

  @typedoc "Nebulex.Stats stat names"
  @type stat_name :: :hits | :misses | :writes | :evictions | :expirations
end
