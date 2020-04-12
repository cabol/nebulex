defmodule Nebulex.SharedTestCase do
  @moduledoc false

  defmacro deftests(text, do: block) do
    quote do
      defmacro __using__(opts) do
        text = unquote(text)
        block = unquote(Macro.escape(block))

        quote do
          @config unquote(opts)
          @cache Keyword.fetch!(@config, :cache)

          describe unquote(text) do
            unquote(block)
          end
        end
      end
    end
  end
end
