defmodule Nebulex.Adapter.Transaction.Options do
  @moduledoc false

  # Transaction options
  opts_defs = [
    keys: [
      type: {:list, :any},
      required: false,
      default: [],
      doc: """
      The list of keys the transaction will lock. Since the lock ID is generated
      based on the key, the transaction uses a fixed lock ID if the option is
      not provided or is an empty list. Then, all subsequent transactions
      without this option (or set to an empty list) are serialized, and
      performance is significantly affected. For that reason, it is recommended
      to pass the list of keys involved in the transaction.
      """
    ],
    nodes: [
      type: {:list, :atom},
      required: false,
      doc: """
      The list of the nodes where to set the lock.

      The default value is `[node()]`.
      """
    ],
    retries: [
      type: {:or, [:non_neg_integer, {:in, [:infinity]}]},
      type_doc: "`:infinity` | `t:non_neg_integer/0`",
      required: false,
      default: :infinity,
      doc: """
      If the key has already been locked by another process and retries are not
      equal to 0, the process sleeps for a while and tries to execute the action
      later. When `:retries` attempts have been made, an exception is raised. If
      `:retries` is `:infinity` (the default), the function will eventually be
      executed (unless the lock is never released).
      """
    ]
  ]

  # Transaction options schema
  @opts_schema NimbleOptions.new!(opts_defs)

  # Transaction options
  @opts Keyword.keys(@opts_schema.schema)

  ## Docs API

  # coveralls-ignore-start

  @spec options_docs() :: binary()
  def options_docs do
    NimbleOptions.docs(@opts_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    opts
    |> Keyword.take(@opts)
    |> NimbleOptions.validate!(@opts_schema)
  end
end
