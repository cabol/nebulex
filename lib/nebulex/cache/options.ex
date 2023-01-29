defmodule Nebulex.Cache.Options do
  @moduledoc """
  Behaviour for option definitions and validation.
  """

  @base_definition [
    otp_app: [
      required: false,
      type: :atom,
      doc: """
      The OTP app.
      """
    ],
    adapter: [
      required: false,
      type: :atom,
      doc: """
      The cache adapter module.
      """
    ],
    cache: [
      required: false,
      type: :atom,
      doc: """
      The defined cache module.
      """
    ],
    name: [
      required: false,
      type: :atom,
      doc: """
      The name of the Cache supervisor process.
      """
    ],
    telemetry_prefix: [
      required: false,
      type: {:list, :atom},
      doc: """
      The telemetry prefix.
      """
    ],
    telemetry: [
      required: false,
      type: :boolean,
      default: true,
      doc: """
      An optional flag to tell the adapters whether Telemetry events should be
      emitted or not.
      """
    ],
    stats: [
      required: false,
      type: :boolean,
      default: false,
      doc: """
      Defines whether or not the cache will provide stats.
      """
    ]
  ]

  @doc false
  def base_definition, do: @base_definition

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Cache.Options

      import unquote(__MODULE__), only: [base_definition: 0]

      @doc false
      def definition, do: unquote(@base_definition)

      @doc false
      def validate!(opts) do
        opts
        |> NimbleOptions.validate(__MODULE__.definition())
        |> format_error()
      end

      defp format_error({:ok, opts}) do
        opts
      end

      defp format_error({:error, %NimbleOptions.ValidationError{message: message}}) do
        raise ArgumentError, message
      end

      defoverridable definition: 0, validate!: 1
    end
  end

  @doc """
  Returns the option definitions.
  """
  @callback definition() :: NimbleOptions.t() | NimbleOptions.schema()

  @doc """
  Validates the given `opts` with the definition returned by `c:definition/0`.
  """
  @callback validate!(opts :: keyword) :: keyword
end
