defmodule Nebulex.Adapters.Multilevel.Options do
  @moduledoc """
  Option definitions for the multilevel adapter.
  """
  use Nebulex.Cache.Options

  definition =
    [
      levels: [
        required: true,
        type: :non_empty_keyword_list,
        doc: """
        The list of the cache levels.
        """
      ],
      model: [
        required: false,
        type: {:in, [:inclusive, :exclusive]},
        default: :inclusive,
        doc: """
        Specifies the cache model: `:inclusive` or `:exclusive`.
        """
      ]
    ] ++ base_definition()

  @definition NimbleOptions.new!(definition)

  @doc false
  def definition, do: @definition
end
