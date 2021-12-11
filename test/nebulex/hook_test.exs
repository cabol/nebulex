defmodule Nebulex.HookTest do
  use ExUnit.Case, async: true

  # alias Nebulex.Hook

  # describe "before" do
  #   defmodule BeforeHookCache do
  #     @moduledoc false
  #     use Nebulex.Hook
  #     @decorate_all before(&Nebulex.HookTest.hook_fun/1)

  #     use Nebulex.Cache,
  #       otp_app: :nebulex,
  #       adapter: Nebulex.Adapters.Local
  #   end

  #   test "hook" do
  #     {:ok, _pid} = BeforeHookCache.start_link()
  #     true = Process.register(self(), :hooked_cache)
  #     _ = BeforeHookCache.new_generation()

  #     refute BeforeHookCache.get!("foo")
  #     assert_receive %Hook{} = hook, 200
  #     assert hook.step == :before
  #     assert hook.module == BeforeHookCache
  #     assert hook.name == :get
  #     assert hook.arity == 2
  #     refute hook.return

  #     assert BeforeHookCache.put!("foo", "bar") == :ok
  #     assert_receive %Hook{} = hook, 200
  #     assert hook.step == :before
  #     assert hook.module == BeforeHookCache
  #     assert hook.name == :put
  #     assert hook.arity == 3
  #     refute hook.return

  #     :ok = BeforeHookCache.stop()
  #   end
  # end

  # describe "after_return" do
  #   defmodule AfterReturnHookCache do
  #     @moduledoc false
  #     use Nebulex.Hook
  #     @decorate_all after_return(&Nebulex.HookTest.hook_fun/1)

  #     use Nebulex.Cache,
  #       otp_app: :nebulex,
  #       adapter: Nebulex.Adapters.Local
  #   end

  #   test "hook" do
  #     {:ok, _pid} = AfterReturnHookCache.start_link()
  #     true = Process.register(self(), :hooked_cache)
  #     _ = AfterReturnHookCache.new_generation()

  #     refute AfterReturnHookCache.get!("foo")
  #     assert_receive %Hook{} = hook, 200
  #     assert hook.module == AfterReturnHookCache
  #     assert hook.name == :get
  #     assert hook.arity == 2
  #     assert hook.step == :after_return
  #     refute hook.return

  #     assert AfterReturnHookCache.put!("foo", "bar") == :ok
  #     assert_receive %Hook{} = hook, 200
  #     assert hook.module == AfterReturnHookCache
  #     assert hook.name == :put
  #     assert hook.arity == 3
  #     assert hook.step == :after_return
  #     assert hook.return == :ok

  #     :ok = AfterReturnHookCache.stop()
  #   end
  # end

  # describe "around" do
  #   defmodule AroundHookCache do
  #     @moduledoc false
  #     use Nebulex.Hook
  #     @decorate_all around(&Nebulex.TestCache.TestHook.track/1)

  #     use Nebulex.Cache,
  #       otp_app: :nebulex,
  #       adapter: Nebulex.Adapters.Local

  #     alias Nebulex.TestCache.TestHook

  #     def init(opts) do
  #       {:ok, pid} = TestHook.start_link()
  #       {:ok, Keyword.put(opts, :hook_pid, pid)}
  #     end
  #   end

  #   test "hook" do
  #     {:ok, _pid} = AroundHookCache.start_link()
  #     true = Process.register(self(), :hooked_cache)
  #     _ = AroundHookCache.new_generation()

  #     refute AroundHookCache.get!("foo")
  #     assert_receive %Hook{module: AroundHookCache, name: :get, arity: 2} = hook, 200
  #     refute hook.return
  #     assert hook.acc >= 0

  #     assert AroundHookCache.put!("foo", "bar") == :ok
  #     assert_receive %Hook{module: AroundHookCache, name: :put, arity: 3} = hook, 200
  #     assert hook.acc >= 0
  #     assert hook.return == :ok

  #     assert AroundHookCache.put!("hello", "world") == :ok
  #     assert_receive %Hook{module: AroundHookCache, name: :put, arity: 3} = hook, 200
  #     assert hook.acc >= 0
  #     assert hook.return == :ok

  #     assert "bar" == AroundHookCache.get!("foo")
  #     assert_receive %Hook{module: AroundHookCache, name: :get, arity: 2} = hook, 200
  #     assert hook.return == "bar"
  #     assert hook.acc >= 0

  #     assert "world" == AroundHookCache.get!("hello")
  #     assert_receive %Hook{module: AroundHookCache, name: :get, arity: 2} = hook, 200
  #     assert hook.return == "world"
  #     assert hook.acc >= 0

  #     :ok = AroundHookCache.stop()
  #   end
  # end

  # describe "exception" do
  #   defmodule ErrorCache do
  #     @moduledoc false
  #     use Nebulex.Hook
  #     @decorate_all around(&Nebulex.TestCache.TestHook.hook_error/1)

  #     use Nebulex.Cache,
  #       otp_app: :nebulex,
  #       adapter: Nebulex.Adapters.Local
  #   end

  #   test "hook" do
  #     {:ok, _pid} = ErrorCache.start_link()

  #     assert_raise RuntimeError, ~r"hook execution failed on step :before with error", fn ->
  #       ErrorCache.get!("foo")
  #     end

  #     :ok = ErrorCache.stop()
  #   end
  # end

  # ## Helpers

  # def hook_fun(%Hook{name: name} = hook) when name in [:get, :put] do
  #   send(self(), hook)
  # end

  # def hook_fun(hook), do: hook
end
