defmodule Bbh.Repo.Migrations.AddFilterAliveToPersonList do
  use Ecto.Migration

  # Lebend / verstorben for the Personenliste block; „all" keeps every existing block as is.
  def change do
    alter table(:block_person_list) do
      add :filter_alive, :string, null: false, default: "all"
    end
  end
end
