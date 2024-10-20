defmodule Nebulex.Dialyzer.CachingDecorators do
  @moduledoc false

  alias Nebulex.Caching.Decorators

  use Nebulex.Caching,
    default_key_generator: &__MODULE__.generate_key/1,
    cache: Cache,
    on_error: :raise,
    match: &Decorators.default_match/1,
    opts: [ttl: :timer.seconds(10)]

  defmodule Account do
    @moduledoc false
    defstruct [:id, :username, :password, :email]

    @type t() :: %__MODULE__{}
  end

  @cache Cache
  @ttl :timer.seconds(3600)

  ## Annotated Functions

  @spec get_account(integer()) :: Account.t()
  @decorate cacheable(cache: @cache, key: {Account, id})
  def get_account(id) do
    %Account{id: id}
  end

  @spec get_account_by_username(binary()) :: Account.t()
  @decorate cacheable(
              cache: dynamic_cache(@cache, Cache),
              key: {Account, username},
              references: & &1.id,
              opts: [ttl: @ttl]
            )
  def get_account_by_username(username) do
    %Account{username: username}
  end

  @spec get_account_by_email(Account.t()) :: Account.t()
  @decorate cacheable(
              cache: YetAnotherCache,
              key: email,
              references: &keyref(&1.id, cache: Cache),
              opts: [ttl: @ttl]
            )
  def get_account_by_email(%Account{email: email} = acct) do
    %{acct | email: email}
  end

  @spec update_account(Account.t()) :: {:ok, Account.t()}
  @decorate cache_put(
              cache: @cache,
              key: {:in, [{Account, acct.id}, {Account, acct.username}]},
              match: &match/1,
              opts: [ttl: @ttl]
            )
  def update_account(%Account{} = acct) do
    {:ok, acct}
  end

  @spec update_account_by_id(binary(), %{optional(atom()) => any()}) :: {:ok, Account.t()}
  @decorate cache_put(cache: Cache, key: {Account, id}, match: &match/1, opts: [ttl: @ttl])
  def update_account_by_id(id, attrs) do
    {:ok, struct(Account, Map.put(attrs, :id, id))}
  end

  @spec delete_account(Account.t()) :: Account.t()
  @decorate cache_evict(
              cache: &cache_fun/1,
              key: {:in, [{Account, acct.id}, {Account, acct.username}]}
            )
  def delete_account(%Account{} = acct) do
    acct
  end

  @spec delete_all_accounts(any()) :: any()
  @decorate cache_evict(cache: &cache_fun/1, all_entries: true)
  def delete_all_accounts(filter) do
    filter
  end

  @spec get_user_key(binary()) :: binary()
  @decorate cacheable(cache: &cache_fun/1, key: &generate_key/1)
  def get_user_key(id), do: id

  @spec update_user_key(binary()) :: binary()
  @decorate cacheable(cache: Cache, key: &generate_key({"custom", &1.args}))
  def update_user_key(id), do: id

  ## Helpers

  defp match({:ok, _} = ok), do: {true, ok}
  defp match({:error, _}), do: false

  def generate_key(ctx), do: :erlang.phash2(ctx)

  def cache_fun(ctx) do
    _ = send(self(), ctx)

    Cache
  end
end
