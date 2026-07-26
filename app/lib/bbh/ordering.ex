defmodule Bbh.Ordering do
  @moduledoc """
  Shared write path for the hand-ordered lists in the app: page blocks
  (`page_blocks.position`), gallery images (`block_gallery_files.sort`) and media
  folders (`media_folders.position`).

  All three answer the same question — "the editor dragged this somewhere, write
  the new order" — and all three answer it the same way, so the transaction lives
  here once instead of in each context.
  """

  alias Bbh.Repo

  @doc """
  Write `items` back in list order, numbering them 0..n-1 through `write_position`
  (a `fn id, position -> … end`), all inside one transaction.

  Renumbering the whole list rather than swapping two stored values is what keeps
  this correct on real data: no column is renumbered on delete, so the values can
  have gaps or an offset (delete the first row and they start at 1), and
  `block_gallery_files.sort` is nullable on top of that. Swapping values then
  either does nothing or writes a duplicate that makes the order ambiguous. The
  lists are a handful of rows each, so rewriting all of them is free.

  Note the renumber writes row by row, so two rows briefly share a value inside
  the transaction. Every ordering column this touches is covered by a plain index
  only; adding a unique index on `(page_id, position)`, `(gallery_id, sort)` or
  `(parent_id, position)` would break it.
  """
  def renumber(items, write_position) do
    Repo.transaction(fn ->
      items
      |> Enum.with_index()
      |> Enum.each(fn {item, position} -> write_position.(item.id, position) end)
    end)
  end

  @doc """
  Move the item at `idx` one step (`:up` | `:down`) and renumber.

  `idx` is `nil` when the row is not in the list at all — a stale id, or a row
  belonging to another parent — which must not blow up on the arithmetic.
  """
  def move_step(items, idx, direction, write_position) when is_integer(idx) do
    to = if direction == :up, do: idx - 1, else: idx + 1

    if to >= 0 and to < length(items) do
      items
      |> List.delete_at(idx)
      |> List.insert_at(to, Enum.at(items, idx))
      |> renumber(write_position)
    else
      # Already at the top/bottom edge — nothing to do.
      {:ok, :noop}
    end
  end

  def move_step(_items, _idx, _direction, _write_position), do: {:error, :not_found}
end
