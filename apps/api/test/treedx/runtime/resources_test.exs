defmodule TreeDx.Runtime.ResourcesTest do
  use ExUnit.Case, async: false
  alias TreeDx.Runtime.Resources

  test "runtime and native cache budgets remain finite with absent empty malformed and exhausted configuration" do
    names =
      ~w(TREEDX_RUNTIME_MEMORY_BUDGET_MB TREEDX_CACHE_MEMORY_FRACTION TREEDX_CACHE_MIN_FREE_MEMORY_MB)

    previous = Map.new(names, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(previous, fn {name, value} ->
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end)
    end)

    Enum.each(names, &System.delete_env/1)

    for value <- [nil, "", "invalid", "0", "-1", "4096garbage"] do
      if value, do: System.put_env(hd(names), value), else: System.delete_env(hd(names))
      assert Resources.memory_budget_bytes() == 4_294_967_296
      assert Resources.cache_budget_bytes() == 939_524_096
      assert Resources.cache_budget_for(:native_log) > 0
    end

    System.put_env(hd(names), "4096")

    for fraction <- ["", "invalid", "0.25garbage", "-0.1", "1.1"] do
      System.put_env("TREEDX_CACHE_MEMORY_FRACTION", fraction)
      assert Resources.cache_budget_bytes() == 939_524_096
    end

    for {fraction, expected} <- [{"0", 0}, {"1", 3_758_096_384}] do
      System.put_env("TREEDX_CACHE_MEMORY_FRACTION", fraction)
      assert Resources.cache_budget_bytes() == expected

      shares =
        Enum.map(
          [:repo_doc, :graph_index, :artifact_index, :native_log],
          &Resources.cache_budget_for/1
        )

      assert Enum.sum(shares) <= expected
      assert Enum.all?(shares, &(&1 >= 0))
    end

    System.delete_env("TREEDX_CACHE_MEMORY_FRACTION")
    System.put_env(hd(names), "256")
    assert Resources.cache_budget_bytes() == 0
    assert Resources.cache_budget_for(:repo_doc) == 0
    assert Resources.cache_budget_for(:native_log) == 0
  end
end
