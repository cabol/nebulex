defmodule Nebulex.Caching.KeyGenerator do
  @moduledoc """
  Cache key generator. Used for creating a key based on the given module,
  function name and its arguments (the module and function name are used
  as context).

  See the default implementation `Nebulex.Caching.SimpleKeyGenerator`.

  ## Caveats when using the key generator

  Since the callback `c:generate/3` is invoked passing the calling module where
  the annotated function is defined, the name of the annotated function, and the
  arguments given to that annotated function, there are some caveats to keep in
  mind:

    * Only arguments explicitly assigned to a variable will be included when
      calling the callback `c:generate/3`.
    * Ignored or underscored arguments will be ignored.
    * Pattern-matching expressions without a variable assignment will be
      ignored. If there is a pattern-matching, it has to be explicitly
      assigned to a variable so it can be included when calling the
      callback `c:generate/3`.

  For example, suppose you have a module with an annotated function:

      defmodule MyApp.SomeModule do
        use Nebulex.Caching

        alias MyApp.{Cache, CustomKeyGenerator}

        @decorate cacheable(cache: Cache, key_generator: CustomKeyGenerator)
        def get_something(x, _ignored, _, {_, _}, [_, _], %{a: a}, %{} = y) do
          # Function's logic
        end
      end

  The generator will be invoked like so:

      MyKeyGenerator.generate(MyApp.SomeModule, :get_something, [x, y])

  Based on the caveats described above, only the arguments `x` and `y` are
  included when calling the callback `c:generate/3`.
  """

  @typedoc "Key generator type"
  @type t :: module

  @doc """
  Generates a key for the given `module`, `function_name`, and its `args`.
  """
  @callback generate(module, function_name :: atom, args :: [term]) :: term
end
