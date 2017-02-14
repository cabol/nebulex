defmodule Nebulex.Version do
  @moduledoc """
  Version Generator Interface.

  The purpose of this module is to allow users implement custom
  version generators. This interface is used by the adapters to
  generate new object versions.

  ## Example

      defmodule MyApp.Timestamper do
        @behaviour Nebulex.Version

        def generate(_) do
          DateTime.utc_now |> DateTime.to_unix(:nanoseconds)
        end
      end

  A good version generation algorithm may be **Vector Clocks**.
  """

  @doc """
  Generates a new `Nebulex.Object.t` version.

  This callback is invoked by the adapter when an object is going to be set.
  The argument passed to the function will be the cached object, and a new
  version must be returned.

  For more information, see the adapters documentation.
  """
  @callback generate(cached_object :: Nebulex.Object.t) :: any
end
