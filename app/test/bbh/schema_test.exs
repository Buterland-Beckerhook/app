defmodule Bbh.SchemaTest do
  use ExUnit.Case, async: true

  test "cast_id/1 accepts a UUID and turns everything else into :error" do
    id = Ecto.UUID.generate()
    assert Bbh.Schema.cast_id(id) == {:ok, id}

    for bad <- ["", "kein-uuid", nil, 42, %{}] do
      assert Bbh.Schema.cast_id(bad) == :error
    end
  end
end
