defmodule Nebulex.Adapters.Local.Options do
  @moduledoc """
  Option definitions for the local adapter.
  """
  use Nebulex.Cache.Options

  definition =
    [
      gc_interval: [
        required: false,
        type: :pos_integer,
        doc: """
        The interval time in milliseconds to garbage collection to run,
        delete the oldest generation and create a new one.
        """
      ],
      max_size: [
        required: false,
        type: :pos_integer,
        doc: """
        The max number of cached entries (cache limit).
        """
      ],
      allocated_memory: [
        required: false,
        type: :pos_integer,
        doc: """
        The max size in bytes for the cache storage.
        """
      ],
      gc_cleanup_min_timeout: [
        required: false,
        type: :pos_integer,
        default: 10_000,
        doc: """
        The min timeout in milliseconds for triggering the next cleanup
        and memory check.
        """
      ],
      gc_cleanup_max_timeout: [
        required: false,
        type: :pos_integer,
        default: 600_000,
        doc: """
        The max timeout in milliseconds for triggering the next cleanup
        and memory check.
        """
      ],
      reset_timer: [
        required: false,
        type: :boolean,
        default: true,
        doc: """
        Whether the GC timer should be reset or not.
        """
      ],
      backend: [
        required: false,
        type: {:in, [:ets, :shards]},
        default: :ets,
        doc: """
        The backend or storage to be used for the adapter.
        Supported backends are: `:ets` and `:shards`.
        """
      ],
      read_concurrency: [
        required: false,
        type: :boolean,
        default: true,
        doc: """
        Since this adapter uses ETS tables internally, this option is used when
        a new table is created; see `:ets.new/2`.
        """
      ],
      write_concurrency: [
        required: false,
        type: :boolean,
        default: true,
        doc: """
        Since this adapter uses ETS tables internally, this option is used when
        a new table is created; see `:ets.new/2`.
        """
      ],
      compressed: [
        required: false,
        type: :boolean,
        default: false,
        doc: """
        Since this adapter uses ETS tables internally, this option is used when
        a new table is created; see `:ets.new/2`.
        """
      ],
      backend_type: [
        required: false,
        type: {:in, [:set, :ordered_set, :bag, :duplicate_bag]},
        default: :set,
        doc: """
        This option defines the type of ETS to be used internally when
        a new table is created; see `:ets.new/2`.
        """
      ],
      partitions: [
        required: false,
        type: :pos_integer,
        doc: """
        This option is only available for `:shards` backend and defines
        the number of partitions to use.
        """
      ],
      backend_opts: [
        required: false,
        doc: """
        This option is built internally for creating the ETS tables
        used by the local adapter underneath.
        """
      ],
      purge_chunk_size: [
        required: false,
        type: :pos_integer,
        default: 100,
        doc: """
        This option is for limiting the max nested match specs based on number
        of keys when purging the older cache generation.
        """
      ]
    ] ++ base_definition()

  @definition NimbleOptions.new!(definition)

  @doc false
  def definition, do: @definition
end
