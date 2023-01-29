defmodule Nebulex.Adapters.Partitioned.Options do
  @moduledoc """
  Option definitions for the partitioned adapter.
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
      ],
      keyslot: [
        required: false,
        type: :atom,
        doc: """
        Defines the module implementing `Nebulex.Adapter.Keyslot` behaviour.
        """
      ],
      join_timeout: [
        required: false,
        type: :pos_integer,
        default: :timer.seconds(180),
        doc: """
        Interval time in milliseconds for joining the running partitioned cache
        to the cluster. This is to ensure it is always joined.
        """
      ]
    ] ++ base_definition()

  @definition NimbleOptions.new!(definition)

  @doc false
  def definition, do: @definition
end
