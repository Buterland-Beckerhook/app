defmodule Bbh.Tickets.Queue do
  @moduledoc """
  The Postfach's queues, maintained by admins (`/admin/postfaecher`): label, the
  address mail to it arrives at (an alias of the collector mailbox), the address replies
  go out from, the signature line under replies, whether the contact form offers it.

  Two queues are fixed: `info` takes whatever no other queue claims, and
  `mitgliedschaft` is where the membership form files — both can be edited, never
  deleted. A queue's `key` is what tickets and grants refer to, so it never changes;
  a queue still in use can be deactivated instead of deleted.

  Served from a `:persistent_term` cache that every write through this module
  refreshes (off in tests).

  On Beta, `TICKET_ADDRESS_PREFIX=beta.` turns every address into its test alias
  (`vorstand@…` → `beta.vorstand@…`), so a copy of Prod's data never sends or routes
  as the real addresses.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Bbh.Repo
  alias Bbh.Tickets.{Grant, Ticket}

  @cache_key {__MODULE__, :all}
  @default "info"
  @protected ~w(info mitgliedschaft)

  @primary_key {:key, :string, autogenerate: false}
  schema "ticket_queues" do
    field :label, :string
    field :inbound_address, :string
    field :reply_address, :string
    field :signature, :string
    field :in_contact_form, :boolean, default: false
    field :position, :integer, default: 0
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  ## Reading

  @doc "All queues, in display order (inactive ones too)."
  def all do
    if cache?() do
      case :persistent_term.get(@cache_key, nil) do
        nil -> tap(load(), &:persistent_term.put(@cache_key, &1))
        queues -> queues
      end
    else
      load()
    end
  end

  defp load, do: Repo.all(from q in __MODULE__, order_by: [asc: q.position, asc: q.label])

  @doc "The queue with this key, or nil."
  def get(key), do: Enum.find(all(), &(&1.key == key))

  @doc "All queue keys — what a ticket's or grant's queue may be."
  def keys, do: Enum.map(all(), & &1.key)

  @doc "The queue requests go to when nothing else decides."
  def default, do: @default

  @doc "Whether this queue is one the app relies on (cannot be deleted)."
  def protected?(key), do: key in @protected

  @doc "Whether `key` names a queue."
  def valid?(key), do: get(key) != nil

  @doc "Display label of a queue."
  def label(key) do
    case get(key) do
      %{label: label} -> label
      nil -> key
    end
  end

  @doc "`{label, key}` of the active queues — for moving tickets and granting."
  def options, do: for(%{active: true} = q <- all(), do: {q.label, q.key})

  @doc "`{label, key}` of the queues a visitor can pick in the contact form."
  def contact_options,
    do: for(%{active: true, in_contact_form: true} = q <- all(), do: {q.label, q.key})

  @doc "Whether the contact form offers this queue."
  def in_contact_form?(key), do: List.keymember?(contact_options(), key, 1)

  @doc "The address mail to this queue arrives at, or nil."
  def inbound_address(key), do: key |> get() |> field_value(:inbound_address) |> prefixed()

  @doc "The address replies from this queue are sent as (its inbound address by default)."
  def reply_address(key) do
    case get(key) do
      nil -> nil
      q -> prefixed(q.reply_address || q.inbound_address)
    end
  end

  @doc "The line naming the queue under a reply and in the sender name; nil: the club only."
  def signature(key), do: key |> get() |> field_value(:signature)

  @doc "The queue whose inbound address is `address` (case-insensitive), or nil."
  def for_address(address) when is_binary(address) do
    address = address |> String.trim() |> String.downcase()

    Enum.find_value(all(), fn q ->
      if (prefixed(q.inbound_address) || "") |> String.downcase() == address, do: q.key
    end)
  end

  def for_address(_), do: nil

  defp field_value(nil, _field), do: nil
  defp field_value(queue, field), do: Map.get(queue, field)

  # TICKET_ADDRESS_PREFIX ("beta.") in front of the local part.
  defp prefixed(nil), do: nil

  defp prefixed(address) do
    case Application.get_env(:bbh, :ticket_address_prefix) do
      prefix when prefix in [nil, ""] -> address
      prefix -> prefix <> address
    end
  end

  ## Writing (admins)

  @doc false
  def changeset(queue, attrs) do
    queue
    |> cast(attrs, [
      :label,
      :inbound_address,
      :reply_address,
      :signature,
      :in_contact_form,
      :position,
      :active
    ])
    |> update_change(:inbound_address, &normalize_address/1)
    |> update_change(:reply_address, &normalize_address/1)
    |> update_change(:signature, &blank_nil/1)
    |> validate_required([:label])
    |> validate_length(:label, max: 60)
    |> validate_length(:signature, max: 60)
    |> validate_format(:inbound_address, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "ist keine E-Mail-Adresse"
    )
    |> validate_format(:reply_address, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "ist keine E-Mail-Adresse"
    )
    |> unique_constraint(:inbound_address,
      name: :ticket_queues_inbound_address_index,
      message: "gehört schon zu einem anderen Postfach"
    )
    |> validate_fixed_queue()
  end

  # `info` must stay reachable; `mitgliedschaft` needs somewhere to answer from.
  defp validate_fixed_queue(changeset) do
    case get_field(changeset, :key) do
      "info" ->
        changeset
        |> validate_required([:inbound_address])
        |> validate_change(:active, fn :active, active ->
          if active, do: [], else: [active: "Allgemein bleibt immer aktiv"]
        end)

      "mitgliedschaft" ->
        validate_change(changeset, :active, fn :active, active ->
          if active, do: [], else: [active: "Mitgliedsanträge bleiben immer aktiv"]
        end)

      _ ->
        changeset
    end
  end

  @doc false
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:key])
    |> update_change(:key, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:key])
    |> validate_format(:key, ~r/^[a-z][a-z0-9_]{1,29}$/,
      message: "nur Kleinbuchstaben, Ziffern und _, beginnt mit einem Buchstaben"
    )
    |> unique_constraint(:key, name: :ticket_queues_pkey, message: "gibt es schon")
    |> changeset(attrs)
  end

  @doc "Creates a queue."
  def create(attrs), do: attrs |> create_changeset() |> Repo.insert() |> refreshed()

  @doc "Updates a queue (never its key)."
  def update(%__MODULE__{} = queue, attrs),
    do: queue |> changeset(attrs) |> Repo.update() |> refreshed()

  @doc """
  Deletes a queue nobody uses: not a fixed one, no tickets, no grants. Otherwise
  `{:error, reason}` — deactivate it instead.
  """
  def delete(%__MODULE__{key: key} = queue) do
    cond do
      protected?(key) -> {:error, :protected}
      Repo.exists?(from t in Ticket, where: t.queue == ^key) -> {:error, :has_tickets}
      Repo.exists?(from g in Grant, where: g.queue_key == ^key) -> {:error, :has_grants}
      true -> queue |> Repo.delete() |> refreshed()
    end
  end

  defp refreshed({:ok, _} = result) do
    if cache?(), do: :persistent_term.erase(@cache_key)
    result
  end

  defp refreshed(error), do: error

  defp normalize_address(nil), do: nil

  defp normalize_address(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> nil
      address -> address
    end
  end

  defp blank_nil(nil), do: nil

  defp blank_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp cache?, do: Application.get_env(:bbh, __MODULE__, [])[:cache] != false
end
