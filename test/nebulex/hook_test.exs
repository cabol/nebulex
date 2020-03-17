defmodule Nebulex.HookTest do
  use ExUnit.Case, async: true

  alias Nebulex.Hook.Event
  alias Nebulex.TestCache.{ErrorHookableCache, HookableCache}

  setup do
    {:ok, pid} = HookableCache.start_link()
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: HookableCache.stop(pid)
    end)
  end

  test "hooks" do
    true = Process.register(self(), :hooked_cache)
    HookableCache.new_generation()

    refute HookableCache.get("foo")
    assert_receive %Event{module: HookableCache, name: :get, arity: 2} = event, 200
    refute event.result
    assert event.acc >= 0

    assert :ok == HookableCache.put("foo", "bar")
    assert_receive %Event{module: HookableCache, name: :put, arity: 3} = event, 200
    assert event.acc >= 0

    assert :ok == HookableCache.put("hello", "world")
    assert_receive %Event{module: HookableCache, name: :put, arity: 3} = event, 200
    assert event.acc >= 0

    assert "bar" == HookableCache.get("foo")
    assert_receive %Event{module: HookableCache, name: :get, arity: 2} = event, 200
    assert event.result == "bar"
    assert event.acc >= 0

    assert "world" == HookableCache.get("hello")
    assert_receive %Event{module: HookableCache, name: :get, arity: 2} = event, 200
    assert event.result == "world"
    assert event.acc >= 0
  end

  test "hooks error" do
    {:ok, pid} = ErrorHookableCache.start_link()

    assert_raise(Nebulex.HookError, ~r"hook execution failed with error", fn ->
      ErrorHookableCache.get("foo")
    end)

    :ok = ErrorHookableCache.stop(pid)
  end
end
