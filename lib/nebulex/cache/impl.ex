defmodule Nebulex.Cache.Impl do
  @moduledoc false

  @doc """
  Helper macro for defining the functions implementing the Cache API.
  """
  defmacro defcacheapi(fun, to: target) do
    {name, args} = Macro.decompose_call(fun)
    all_args = defcacheapi_all_args(args)

    quote do
      @impl true
      def unquote(name)(unquote_splicing(args)) do
        unquote(name)(
          get_dynamic_cache(),
          unquote_splicing(all_args)
        )
      end

      @impl true
      def unquote(name)(dynamic_cache, unquote_splicing(all_args)) do
        unquote(target).unquote(name)(dynamic_cache, unquote_splicing(all_args))
      end
    end
  end

  defp defcacheapi_all_args(args) do
    Enum.map(args, fn
      {:\\, _, [arg, _]} -> arg
      arg -> arg
    end)
  end
end
