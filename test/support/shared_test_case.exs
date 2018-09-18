defmodule Nebulex.SharedTestCase do
  defmacro deftests(do: block) do
    quote do
      defmacro __using__(opts) do
        block = unquote(Macro.escape(block))

        quote do
          @config unquote(opts)
          @cache Keyword.fetch!(@config, :cache)

          unquote(block)
        end
      end
    end
  end
end
