defmodule Bbh.Redirects.Redirect do
  @moduledoc """
  An editor-managed redirect (Weiterleitung).

  `source_path` is stored normalized (see `Bbh.Redirects.normalize_path/1`), so a rule
  matches regardless of case, percent-encoding or a trailing slash. A trailing `/*`
  turns it into a prefix rule. Redirects are only consulted for requests that would
  otherwise 404, so a rule can never shadow a live page.
  """
  use Bbh.Schema

  alias Bbh.Redirects

  schema "redirects" do
    field :source_path, :string
    field :target, :string
    field :permanent, :boolean, default: true
    field :note, :string
    field :hits, :integer, default: 0
    field :last_hit_at, :utc_datetime

    timestamps()
  end

  @max_length 2000

  @doc false
  def changeset(redirect, attrs) do
    redirect
    |> cast(attrs, [:source_path, :target, :permanent, :note])
    |> update_change(:source_path, &Redirects.normalize_path/1)
    |> update_change(:target, &String.trim/1)
    |> validate_required([:source_path, :target])
    |> validate_length(:source_path, max: @max_length)
    |> validate_length(:target, max: @max_length)
    |> validate_source()
    |> validate_target()
    |> validate_no_loop()
    |> unique_constraint(:source_path,
      message: "für diesen Pfad gibt es schon eine Weiterleitung"
    )
  end

  @doc "Whether a (normalized) source is a prefix rule (`/…/*`)."
  def prefix_source?(source) when is_binary(source), do: String.ends_with?(source, "/*")

  defp validate_source(changeset) do
    validate_change(changeset, :source_path, fn :source_path, source ->
      cond do
        source == "/" ->
          [source_path: "die Startseite kann nicht weitergeleitet werden"]

        source == "/*" ->
          [source_path: "eine Weiterleitung für alle Pfade ist nicht erlaubt"]

        source |> String.trim_trailing("/*") |> String.contains?("*") ->
          [source_path: "„*“ ist nur als letztes Segment („/…/*“) erlaubt"]

        true ->
          []
      end
    end)
  end

  defp validate_target(changeset) do
    validate_change(changeset, :target, fn :target, target ->
      if Redirects.valid_target?(target),
        do: [],
        else: [target: "muss mit „/“ beginnen oder eine http(s)-Adresse sein"]
    end)
  end

  # A relative target that the rule itself would catch again redirects in a circle.
  defp validate_no_loop(changeset) do
    source = get_field(changeset, :source_path)
    target = get_field(changeset, :target)

    if is_binary(source) and is_binary(target) and String.starts_with?(target, "/") and
         Redirects.source_matches?(source, Redirects.normalize_path(target)) do
      add_error(changeset, :target, "würde wieder auf diese Weiterleitung zeigen")
    else
      changeset
    end
  end
end
