defmodule BbhWeb.AdminListTest do
  use ExUnit.Case, async: true

  alias BbhWeb.AdminList

  defp rows do
    [
      %{name: "Charlie", n: 3, at: ~U[2025-01-03 00:00:00Z]},
      %{name: "alpha", n: 1, at: ~U[2025-03-01 00:00:00Z]},
      %{name: "Bravo", n: 2, at: nil}
    ]
  end

  defp opts do
    [
      search: [& &1.name],
      sort: %{"name" => & &1.name, "n" => & &1.n, "at" => & &1.at}
    ]
  end

  test "default sort ascending, case-insensitive on strings" do
    state = AdminList.init(sort: "name", dir: :asc)
    meta = AdminList.process(rows(), state, opts())
    assert Enum.map(meta.entries, & &1.name) == ["alpha", "Bravo", "Charlie"]
    assert meta.total == 3
    assert meta.total_pages == 1
  end

  test "descending sort" do
    state = AdminList.init(sort: "n", dir: :desc)
    meta = AdminList.process(rows(), state, opts())
    assert Enum.map(meta.entries, & &1.n) == [3, 2, 1]
  end

  test "datetimes sort chronologically and nil sorts last" do
    state = AdminList.init(sort: "at", dir: :asc)
    meta = AdminList.process(rows(), state, opts())
    assert Enum.map(meta.entries, & &1.name) == ["Charlie", "alpha", "Bravo"]
  end

  test "filter matches substring case-insensitively" do
    state = %{AdminList.init() | q: "ra"}
    meta = AdminList.process(rows(), state, opts())
    assert Enum.map(meta.entries, & &1.name) == ["Bravo"]
    assert meta.total == 1
  end

  test "toggle_sort flips direction on same key and resets on a new key" do
    state = AdminList.init(sort: "name", dir: :asc)
    assert %{sort: "name", dir: :desc} = AdminList.toggle_sort(state, "name")
    assert %{sort: "n", dir: :asc} = AdminList.toggle_sort(state, "n")
  end

  test "pagination slices and clamps the page" do
    state = %{AdminList.init(sort: "n", dir: :asc) | page: 3}
    meta = AdminList.process(rows(), state, Keyword.put(opts(), :per_page, 2))
    assert meta.total_pages == 2
    assert meta.page == 2
    assert Enum.map(meta.entries, & &1.n) == [3]
  end
end
