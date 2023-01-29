defmodule Nebulex.FakeAdapter do
  @moduledoc false

  ## Nebulex.Adapter

  @doc false
  defmacro __before_compile__(_), do: :ok

  @doc false
  def init(_opts) do
    child_spec = Supervisor.child_spec({Agent, fn -> :ok end}, id: {Agent, 1})

    {:ok, child_spec, %{}}
  end

  ## Nebulex.Adapter.Entry

  @doc false
  def fetch(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def put(_, :error, reason, _, _, _), do: {:error, reason}
  def put(_, _, _, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def delete(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def take(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def has_key?(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def ttl(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def expire(_, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def touch(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def update_counter(_, _, _, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def get_all(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def put_all(_, _, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  ## Nebulex.Adapter.Queryable

  @doc false
  def execute(_, _, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def stream(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  ## Nebulex.Adapter.Persistence

  @doc false
  def dump(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def load(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  ## Nebulex.Adapter.Stats

  @doc false
  def stats(_), do: {:error, %Nebulex.Error{reason: :error}}

  ## Nebulex.Adapter.Transaction

  @doc false
  def transaction(_, _, _), do: {:error, %Nebulex.Error{reason: :error}}

  @doc false
  def in_transaction?(_), do: {:error, %Nebulex.Error{reason: :error}}
end
