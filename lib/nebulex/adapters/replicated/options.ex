defmodule Nebulex.Adapters.Replicated.Options do
  @moduledoc """
  Option definitions for the replicated adapter.
  """
  use Nebulex.Cache.Options

  definition =
    [
      primary: [
        required: false,
        type: :keyword_list,
        doc: """
        The options that will be passed to the adapter associated with the
        local primary storage.
        """
      ]
    ] ++ base_definition()

  @definition NimbleOptions.new!(definition)

  @doc false
  def definition, do: @definition
end
