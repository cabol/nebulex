defmodule Nebulex.Stats do
  @moduledoc """
  Stats data type.

  Stats struct defines two main keys:

  * `:measurements` - A map with the measurements provided by the underlying
    adapter.
  * `:metadata` - A map for including additional information; also provided
    by the underlying adapter.

  ## Measurements

  The following measurements are expected to be present and fed by the
  underlying adapter:

    * `:evictions` - When a cache entry is removed.
    * `:expirations` - When a cache entry is expired.
    * `:hits` - When a key is looked up in cache and found.
    * `:misses` - When a key is looked up in cache but not found.
    * `:updates` - When an existing cache entry is or updated.
    * `:writes` - When a cache entry is inserted or overwritten.

  ## Metadata

  Despite the adapters can include any additional or custom metadata, It is
  recommended they include the following keys:

    * `:cache` - The cache module, or the name (if an explicit name has been
      given to the cache).

  **IMPORTANT:** Since the adapter may include any additional or custom
  measurements, as well as metadata, it is recommended to check out the
  adapter's documentation.
  """

  # Stats data type
  defstruct measurements: %{},
            metadata: %{}

  @typedoc "Nebulex.Stats data type"
  @type t :: %__MODULE__{
          measurements: %{optional(atom) => term},
          metadata: %{optional(atom) => term}
        }
end
