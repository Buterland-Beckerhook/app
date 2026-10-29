defmodule Bbh.Tickets.Queue do
  @moduledoc """
  The Postfach's queues — a fixed list in code, like `Bbh.Calendar.Event.calendars/0`.

  Each queue has a label, an inbound address (mail to it lands in the queue; nil for
  `mitgliedschaft`, which only the membership form fills) and a reply address (replies
  go out from it). Who works a queue is decided per user in the user administration
  (`Bbh.Tickets.Grants`), never here.

  Addresses default to the club's and can be overridden with
  `TICKET_QUEUE_ADDRESSES="info=info@…,vorstand=vorstand@…"` (Beta uses test aliases).
  """

  @domain "buterland-beckerhook.de"

  # {key, label, local part of the inbound address (nil: none), in the contact form?}
  @queues [
    {"info", "Allgemein", "info", true},
    {"vorstand", "Vorstand", "vorstand", true},
    {"offiziere", "Offiziere", "offiziere", true},
    {"jungschuetzen", "Jungschützen", "jungschuetzen", true},
    {"kinderfest", "Kinderfestausschuss", "kinderfestausschuss", true},
    {"webmaster", "Website", "webmaster", false},
    {"mitgliedschaft", "Mitgliedsanträge", nil, false}
  ]

  @keys Enum.map(@queues, &elem(&1, 0))

  @doc "All queue keys, in display order."
  def keys, do: @keys

  @doc "The queue requests go to when nothing else decides."
  def default, do: "info"

  @doc "Whether `key` names a queue."
  def valid?(key), do: key in @keys

  @doc "Display label of a queue."
  def label(key) do
    case List.keyfind(@queues, key, 0) do
      {_, label, _, _} -> label
      nil -> key
    end
  end

  @doc "`{label, key}` options for a select or checkbox list."
  def options, do: for({key, label, _, _} <- @queues, do: {label, key})

  @doc "`{label, key}` options of the queues a visitor can pick in the contact form."
  def contact_options, do: for({key, label, _, true} <- @queues, do: {label, key})

  @doc "Whether the contact form offers this queue."
  def in_contact_form?(key), do: List.keymember?(contact_options(), key, 1)

  @doc "The address mail to this queue arrives at, or nil."
  def inbound_address(key) do
    case Map.fetch(overrides(), key) do
      {:ok, address} ->
        address

      :error ->
        case List.keyfind(@queues, key, 0) do
          {_, _, nil, _} -> nil
          {_, _, local, _} -> "#{local}@#{@domain}"
          nil -> nil
        end
    end
  end

  @doc """
  The address replies from this queue are sent as. Membership applications are
  answered by the Vorstand, so `mitgliedschaft` replies come from the Vorstand's address.
  """
  def reply_address("mitgliedschaft"), do: inbound_address("vorstand")
  def reply_address(key), do: inbound_address(key)

  @doc "The queue whose inbound address is `address` (case-insensitive), or nil."
  def for_address(address) when is_binary(address) do
    address = address |> String.trim() |> String.downcase()
    Enum.find(@keys, fn key -> (inbound_address(key) || "") |> String.downcase() == address end)
  end

  def for_address(_), do: nil

  defp overrides do
    :bbh
    |> Application.get_env(:ticket_queue_addresses, "")
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn entry ->
      case String.split(entry, "=", parts: 2) do
        [key, address] -> [{String.trim(key), String.trim(address)}]
        _ -> []
      end
    end)
    |> Map.new()
  end
end
