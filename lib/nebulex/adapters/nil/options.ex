defmodule Nebulex.Adapters.Nil.Options do
  @moduledoc """
  Options for the `Nebulex.Adapters.Nil` adapter.
  """

  # Runtime shared options
  runtime_shared_opts = [
    before: [
      type: {:fun, 0},
      required: false,
      doc: """
      Pre-hook function. It calls the given function before the cache command
      is executed.
      """
    ],
    after_return: [
      type: {:fun, 1},
      required: false,
      doc: """
      Post-hook function. It calls the given function after the cache command
      is executed, and the returned result is passed as an argument.
      """
    ]
  ]

  # Runtime shared options schema
  @runtime_shared_opts_schema NimbleOptions.new!(runtime_shared_opts)

  # Runtime shared options
  @runtime_shared_opts Keyword.keys(@runtime_shared_opts_schema.schema)

  ## Docs API

  # coveralls-ignore-start

  @spec runtime_shared_options_docs() :: binary()
  def runtime_shared_options_docs do
    NimbleOptions.docs(@runtime_shared_opts_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @spec validate_runtime_shared_opts!(keyword()) :: keyword()
  def validate_runtime_shared_opts!(opts) do
    runtime_shared_opts =
      opts
      |> Keyword.take(@runtime_shared_opts)
      |> NimbleOptions.validate!(@runtime_shared_opts_schema)

    Keyword.merge(opts, runtime_shared_opts)
  end
end
