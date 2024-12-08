defmodule Nebulex.Cache.QuerySpec do
  # A query specification is a `t:keyword/0` with a set of options defining
  # the desired query.
  @moduledoc false

  # Query-spec option definitions
  query_spec = [
    in: [
      type: {:list, :any},
      required: false,
      doc: """
      The list of keys to fetch. The value to return depends on the `:select`
      option. The `:in` option is a predefined query meant to fetch multiple
      keys simultaneously.

      If present, it overrides the `:query` option and instructs the underlying
      adapter to match the entries associated with the set of keys requested.
      For every key that does not hold a value or does not exist, it is ignored
      and not added to the returned list.
      """
    ],
    query: [
      type: :any,
      required: false,
      default: nil,
      doc: """
      The query specification to match entries in the cache.

      If present and set to `nil`, it matches all entries in the cache. The
      `nil` is a predefined value all adapters must support. Other than that,
      the value depends entirely on the adapter. The adapter is responsible
      for defining the query or matching specification. For example, the
      `Nebulex.Adapters.Local` adapter supports the
      [**"ETS Match Spec"**](https://www.erlang.org/doc/man/ets#match_spec).
      """
    ],
    select: [
      type: {:in, [:key, :value, {:key, :value}, :entry]},
      required: false,
      default: {:key, :value},
      doc: """
      Selects which fields to choose from the entry.

      The possible values are:

        * `{:key, :value}` - (Default) Selects the key and the value from
          the entry. They are returned as a tuple `{key, value}`.
        * `:key` - Selects the key from the entry.
        * `:value` - Selects the value from the entry.
        * `:entry` - Selects the whole entry with its fields (use it carefully).
          The adapter defines the entry, the structure, and its fields.
          Therefore, Nebulex recommends checking the adapter's documentation to
          understand the entry's structure with its fields and to verify if the
          select option is supported.

      """
    ]
  ]

  # Query options schema
  @query_spec_schema NimbleOptions.new!(query_spec)

  ## Docs API

  # coveralls-ignore-start

  @spec options_docs() :: binary()
  def options_docs do
    NimbleOptions.docs(@query_spec_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @compile {:inline, validate!: 1}
  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    NimbleOptions.validate!(opts, @query_spec_schema)
  end
end
