defmodule Bbh.Media.FoldersTest do
  use Bbh.DataCase, async: true

  alias Bbh.Media
  alias Bbh.Media.Folder
  alias Bbh.Media.Upload

  import Bbh.ContentFixtures, only: [upload_fixture: 1]

  describe "folders" do
    test "creates three levels but rejects a fourth" do
      {:ok, root} = Media.Folders.create_folder(%{"name" => "Archiv"})
      assert is_nil(root.parent_id)

      {:ok, year} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => root.id})
      assert year.parent_id == root.id

      {:ok, category} =
        Media.Folders.create_folder(%{"name" => "Schützenfest", "parent_id" => year.id})

      assert category.parent_id == year.id

      assert {:error, changeset} =
               Media.Folders.create_folder(%{"name" => "zu-tief", "parent_id" => category.id})

      assert %{parent_id: ["Ordner dürfen nur 3 Ebenen tief sein"]} = errors_on(changeset)
    end

    test "get_folder/1 loads the whole path for a third-level folder" do
      {:ok, root} = Media.Folders.create_folder(%{"name" => "Archiv"})
      {:ok, year} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => root.id})

      {:ok, category} =
        Media.Folders.create_folder(%{"name" => "Schützenfest", "parent_id" => year.id})

      assert ["Archiv", "2026", "Schützenfest"] ==
               category.id |> Media.Folders.get_folder() |> Folder.path() |> Enum.map(& &1.name)
    end

    test "rejects duplicate names within the same parent" do
      {:ok, _} = Media.Folders.create_folder(%{"name" => "Bilder"})
      assert {:error, changeset} = Media.Folders.create_folder(%{"name" => "Bilder"})
      assert %{name: [_]} = errors_on(changeset)
    end

    test "filters uploads by folder and moves them between folders" do
      {:ok, folder} = Media.Folders.create_folder(%{"name" => "Presse"})
      filed = upload_fixture(folder_id: folder.id)
      _unfiled = upload_fixture(%{})

      assert [%{id: id}] = Media.list_uploads(folder: folder.id)
      assert id == filed.id
      assert [_only_root] = Media.list_uploads(folder: :root)

      {:ok, moved} = Media.move_upload(filed, nil)
      assert is_nil(moved.folder_id)
      assert Media.list_uploads(folder: folder.id) == []
    end

    test "deleting a folder unfiles its media" do
      {:ok, folder} = Media.Folders.create_folder(%{"name" => "Alt"})
      upload = upload_fixture(folder_id: folder.id)

      {:ok, _} = Media.Folders.delete_folder(admin_scope(), folder)

      assert Repo.get!(Upload, upload.id).folder_id == nil
      refute Repo.get(Folder, folder.id)
    end

    test "deleting a folder is admin-only" do
      {:ok, folder} = Media.Folders.create_folder(%{"name" => "Alt"})
      editor = Bbh.Accounts.Scope.for_user(Bbh.AccountsFixtures.user_fixture())

      assert {:error, :unauthorized} = Media.Folders.delete_folder(editor, folder)
      assert Repo.get(Folder, folder.id)
    end

    test "an unknown or malformed folder id is a miss, not a crash" do
      refute Media.Folders.get_folder(Ecto.UUID.generate())
      refute Media.Folders.get_folder("nicht-mal-eine-uuid")
      refute Media.Folders.get_folder("")
      refute Media.Folders.get_folder(nil)
    end

    test "list_uploads(folder: :all) spans filed and unfiled media" do
      {:ok, folder} = Media.Folders.create_folder(%{"name" => "Presse"})
      filed = upload_fixture(folder_id: folder.id)
      unfiled = upload_fixture(%{})

      assert Media.list_uploads(folder: :all) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([filed.id, unfiled.id])
    end
  end

  describe "folder ordering" do
    setup do
      {:ok, a} = Media.Folders.create_folder(%{"name" => "A"})
      {:ok, b} = Media.Folders.create_folder(%{"name" => "B"})
      {:ok, c} = Media.Folders.create_folder(%{"name" => "C"})
      %{a: a, b: b, c: c}
    end

    defp names(parent_id \\ nil),
      do: Media.Folders.list_subfolders(parent_id) |> Enum.map(& &1.name)

    defp positions(parent_id \\ nil),
      do: Media.Folders.list_subfolders(parent_id) |> Enum.map(& &1.position)

    test "a new folder is appended to the bottom of its level", ctx do
      assert [0, 1, 2] == positions()
      assert ctx.c.position == 2

      {:ok, sub} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => ctx.a.id})
      assert sub.position == 0
      {:ok, sub2} = Media.Folders.create_folder(%{"name" => "2025", "parent_id" => ctx.a.id})
      assert sub2.position == 1
    end

    test "moving reorders the level and keeps positions gapless from 0", ctx do
      {:ok, _} = Media.Folders.move_folder(ctx.c, nil, 0)

      assert ["C", "A", "B"] == names()
      assert [0, 1, 2] == positions()
    end

    test "ordering beats the alphabet everywhere folders are listed", ctx do
      {:ok, _} = Media.Folders.move_folder(ctx.c, nil, 0)

      assert ["C", "A", "B"] == Media.Folders.list_root_folders() |> Enum.map(& &1.name)
      assert ["C", "A", "B"] == Media.Folders.child_folders(nil) |> Enum.map(& &1.name)

      # The editor's folder select and the picker read through the same functions.
      assert [{"— Kein Ordner —", ""}, {"C", _}, {"A", _}, {"B", _}] =
               Media.Folders.folder_options()
    end

    test "a negative index is clamped to the front, not read as an offset from the end", ctx do
      # -1 is the one index that tells clamped from unclamped: List.insert_at/3 reads it
      # as "last", clamp/2 as "first". Larger negatives (-5) and overshoots (99) are
      # clamped identically by both, so they would prove nothing.
      {:ok, _} = Media.Folders.move_folder(ctx.a, nil, -1)
      assert ["A", "B", "C"] == names()

      {:ok, _} = Media.Folders.move_folder(ctx.c, nil, -1)
      assert ["C", "A", "B"] == names()
    end

    test "lifting a sub-folder back to the top level places it by index", ctx do
      {:ok, child} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => ctx.a.id})

      # The Alt+Left path, and the one where the moved folder carries a stale position
      # (0, from its old level) into a level that already has a folder at 0.
      {:ok, moved} = Media.Folders.move_folder(child, nil, 1)

      refute moved.parent_id
      assert moved.position == 1
      assert ["A", "2026", "B", "C"] == names()
      assert [0, 1, 2, 3] == positions()
    end

    test "a non-integer position is clamped to the end rather than crashing", ctx do
      # clamp/2's catch-all clause is the actual defence against a hand-built payload.
      {:ok, _} = Media.Folders.move_folder(ctx.a, nil, nil)
      assert ["B", "C", "A"] == names()

      {:ok, _} = Media.Folders.move_folder(ctx.b, nil, "0")
      assert ["C", "A", "B"] == names()
    end

    test "nesting a leaf folder renumbers both levels", ctx do
      {:ok, moved} = Media.Folders.move_folder(ctx.b, ctx.a.id, 0)

      assert moved.parent_id == ctx.a.id
      assert ["B"] == names(ctx.a.id)
      # The level B left behind closes its gap instead of keeping a hole at 1.
      assert ["A", "C"] == names()
      assert [0, 1] == positions()
    end

    test "nests a folder together with its sub-folders while the branch fits", ctx do
      {:ok, child} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => ctx.a.id})

      {:ok, moved} = Media.Folders.move_folder(ctx.a, ctx.b.id, 0)

      assert moved.parent_id == ctx.b.id
      assert Repo.get!(Folder, child.id).parent_id == ctx.a.id
    end

    test "refuses a move that would push a sub-folder past the cap", ctx do
      {:ok, child} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => ctx.a.id})

      {:ok, _grandchild} =
        Media.Folders.create_folder(%{"name" => "Fest", "parent_id" => child.id})

      # A itself would land on level 2, which is fine — its grandchild on level 4 is not.
      assert {:error, changeset} = Media.Folders.move_folder(ctx.a, ctx.b.id, 0)
      assert %{parent_id: [_]} = errors_on(changeset)

      # Rolled back whole: neither the parent nor the ordering moved.
      assert Repo.get!(Folder, ctx.a.id).parent_id == nil
      assert ["A", "B", "C"] == names()
    end

    test "refuses to drop a folder into one of its own sub-folders", ctx do
      {:ok, child} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => ctx.a.id})

      assert {:error, changeset} = Media.Folders.move_folder(ctx.a, child.id, 0)
      assert %{parent_id: ["Ordner kann nicht in sich selbst liegen" | _]} = errors_on(changeset)
      assert Repo.get!(Folder, ctx.a.id).parent_id == nil
    end

    test "a malformed target id is rejected, not read as the top level", ctx do
      {:ok, _} = Media.Folders.move_folder(ctx.b, ctx.a.id, 0)

      # Silently treating garbage as nil would yank the folder out to the top level —
      # a move nobody asked for, and one the editor could not tell from a no-op.
      assert {:error, changeset} = Media.Folders.move_folder(ctx.b, "nicht-mal-eine-uuid", 0)
      assert %{parent_id: [_]} = errors_on(changeset)
      assert Repo.get!(Folder, ctx.b.id).parent_id == ctx.a.id
    end

    test "an uppercase target id still finds its folder", ctx do
      {:ok, moved} = Media.Folders.move_folder(ctx.b, String.upcase(ctx.a.id), 0)

      assert moved.parent_id == ctx.a.id
      # The load-bearing half: the id is also the key the *level* is renumbered under,
      # and list_subfolders/1 casts it. Without normalisation Postgres still matches the
      # row, so only reading the level back proves the canonical form was used.
      assert ["B"] == names(ctx.a.id)
      assert [0] == positions(ctx.a.id)
    end

    test "refuses to drop a folder into itself", ctx do
      assert {:error, changeset} = Media.Folders.move_folder(ctx.a, ctx.a.id, 0)
      assert %{parent_id: [_]} = errors_on(changeset)
      assert Repo.get!(Folder, ctx.a.id).parent_id == nil
    end

    test "refuses to move onto a name already taken on the target level", ctx do
      {:ok, _taken} = Media.Folders.create_folder(%{"name" => "B", "parent_id" => ctx.a.id})

      # The unique index fires mid-transaction; Ecto has to resolve it to a changeset
      # error via a savepoint rather than poisoning the surrounding transaction. The
      # composite constraint reports on its first field, so the message the editor sees
      # arrives under :parent_id.
      assert {:error, changeset} = Media.Folders.move_folder(ctx.b, ctx.a.id, 0)
      assert %{parent_id: ["Ordner mit diesem Namen existiert bereits"]} = errors_on(changeset)

      assert Repo.get!(Folder, ctx.b.id).parent_id == nil
      assert ["A", "B", "C"] == names()
    end

    test "nests a leaf on the third level but refuses a fourth", ctx do
      {:ok, child} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => ctx.a.id})
      {:ok, _} = Media.Folders.move_folder(ctx.b, child.id, 0)
      assert Repo.get!(Folder, ctx.b.id).parent_id == child.id

      assert {:error, changeset} = Media.Folders.move_folder(ctx.c, ctx.b.id, 0)
      assert %{parent_id: [_]} = errors_on(changeset)
      assert Repo.get!(Folder, ctx.c.id).parent_id == nil
    end
  end

  describe "list_folder_tree/0" do
    test "returns both levels in editor order, counting what each node lists" do
      {:ok, presse} = Media.Folders.create_folder(%{"name" => "Presse"})
      {:ok, satzung} = Media.Folders.create_folder(%{"name" => "Satzungen"})
      {:ok, y2026} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => presse.id})

      upload_fixture(folder_id: presse.id)
      upload_fixture(folder_id: y2026.id)
      upload_fixture(folder_id: y2026.id)
      upload_fixture(%{})

      {:ok, _} = Media.Folders.move_folder(satzung, nil, 0)

      tree = Media.Folders.list_folder_tree()

      assert ["Satzungen", "Presse"] == Enum.map(tree.roots, & &1.name)
      assert [[], ["2026"]] == Enum.map(tree.roots, fn r -> Enum.map(r.children, & &1.name) end)

      # The whole branch, because that is what clicking the node now lists: Presse holds
      # one file itself and two in its sub-folder.
      assert tree.counts[presse.id] == 3
      assert tree.counts[y2026.id] == 2
      assert tree.counts[satzung.id] == 0

      # Summed from the direct counts, so the branch fold cannot double-count a parent.
      assert tree.total == 4
      assert tree.unfiled == 1
    end

    test "builds and counts the third level" do
      {:ok, archiv} = Media.Folders.create_folder(%{"name" => "Archiv"})
      {:ok, y2026} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => archiv.id})

      {:ok, fest} =
        Media.Folders.create_folder(%{"name" => "Schützenfest", "parent_id" => y2026.id})

      upload_fixture(folder_id: fest.id)
      upload_fixture(folder_id: fest.id)
      upload_fixture(folder_id: y2026.id)

      tree = Media.Folders.list_folder_tree()

      assert [%{children: [%{name: "2026", children: [%{name: "Schützenfest"}]}]}] = tree.roots
      assert tree.counts[fest.id] == 2
      assert tree.counts[y2026.id] == 3
      assert tree.counts[archiv.id] == 3
      assert tree.total == 3

      assert Enum.sort([archiv.id, y2026.id, fest.id]) ==
               Enum.sort(Media.Folders.branch_ids(tree, archiv.id))

      assert [{"— Kein Ordner —", ""}, {"Archiv", _}, {"Archiv / 2026", _}, {label, _}] =
               Media.Folders.folder_options(tree.roots)

      assert label == "Archiv / 2026 / Schützenfest"
    end

    test "a parent whose pictures all live in its sub-folder counts them anyway" do
      # The case ADR 0006 recorded as reading 0 — the branch scope is what fixes it.
      {:ok, presse} = Media.Folders.create_folder(%{"name" => "Presse"})
      {:ok, y2026} = Media.Folders.create_folder(%{"name" => "2026", "parent_id" => presse.id})

      upload_fixture(folder_id: y2026.id)
      upload_fixture(folder_id: y2026.id)

      tree = Media.Folders.list_folder_tree()

      assert tree.counts[presse.id] == 2
      assert tree.counts[y2026.id] == 2
      # The library's default lists a folder alone, so it counts what is filed right there.
      assert tree.direct == %{y2026.id => 2}
      assert tree.total == 2
      assert tree.unfiled == 0
    end

    test "counts are zero on an empty library" do
      # Equality, not a pattern: `%{} = %{a: 1}` matches in Elixir, so `counts: %{}` in a
      # pattern would accept any counts at all.
      assert Media.Folders.list_folder_tree() ==
               %{roots: [], counts: %{}, direct: %{}, total: 0, unfiled: 0}
    end
  end

  defp admin_scope, do: Bbh.Accounts.Scope.for_user(Bbh.AccountsFixtures.admin_user_fixture())
end
