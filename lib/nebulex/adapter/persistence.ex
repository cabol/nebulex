defmodule Nebulex.Adapter.Persistence do
  @moduledoc ~S"""
  Specifies the adapter persistence API.

  ## Default implementation

  This module provides a default implementation that uses `File` and `Stream`
  under-the-hood. For dumping a cache to a file, the entries are streamed from
  the cache and written in chunks (one chunk per line), and each chunk contains
  N number of entries. For loading the entries from a file, the file is read
  and streamed line-by-line, so that the entries collected on each line are
  inserted in streaming fashion as well.

  The default implementation accepts the following options only for `dump`
  operation (there are not options for `load`):

    * `entries_per_line` - The number of entries to be written per line in the
      file. Defaults to `10`.

    * `compression` - The compression level. The values are the same as
      `:erlang.term_to_binary /2`. Defaults to `6`.

  See `c:Nebulex.Cache.dump/2` and `c:Nebulex.Cache.load/2` for more
  information.
  """

  @doc """
  Dumps a cache to the given file `path`.

  Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

  See `c:Nebulex.Cache.dump/2`.
  """
  @callback dump(Nebulex.Adapter.adapter_meta(), Path.t(), Nebulex.Cache.opts()) ::
              :ok | {:error, term}

  @doc """
  Loads a dumped cache from the given `path`.

  Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

  See `c:Nebulex.Cache.load/2`.
  """
  @callback load(Nebulex.Adapter.adapter_meta(), Path.t(), Nebulex.Cache.opts()) ::
              :ok | {:error, term}

  alias Nebulex.Entry

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Nebulex.Adapter.Persistence

      # sobelow_skip ["Traversal.FileModule"]
      @impl true
      def dump(%{cache: cache}, path, opts) do
        path
        |> File.open([:read, :write], fn io_dev ->
          nil
          |> cache.stream(return: :entry)
          |> Stream.filter(&(not Entry.expired?(&1)))
          |> Stream.map(&{&1.key, &1.value})
          |> Stream.chunk_every(Keyword.get(opts, :entries_per_line, 10))
          |> Enum.each(fn entries ->
            bin = Entry.encode(entries, get_compression(opts))
            :ok = IO.puts(io_dev, bin)
          end)
        end)
        |> handle_response()
      end

      # sobelow_skip ["Traversal.FileModule"]
      @impl true
      def load(%{cache: cache}, path, opts) do
        path
        |> File.open([:read], fn io_dev ->
          io_dev
          |> IO.stream(:line)
          |> Stream.map(&String.trim/1)
          |> Enum.each(fn line ->
            entries = Entry.decode(line, [:safe])
            cache.put_all(entries, opts)
          end)
        end)
        |> handle_response()
      end

      defoverridable dump: 3, load: 3

      ## Helpers

      defp handle_response({:ok, _}), do: :ok
      defp handle_response({:error, _} = error), do: error

      defp get_compression(opts) do
        case Keyword.get(opts, :compression) do
          value when is_integer(value) and value >= 0 and value < 10 ->
            [compressed: value]

          _ ->
            [:compressed]
        end
      end
    end
  end
end
