defmodule BbhWeb.MCP.Args do
  @moduledoc """
  Reads tool arguments out of the string-keyed map a JSON-RPC call carries.

  Tool arguments are model-generated, so they are wrong in ordinary ways: a missing
  required field, a number sent as `"3"`, a lone string where a list belongs. These
  helpers normalize what is recoverable and return a message the model can act on for
  what is not — the error text is part of the tool's interface, not a log line.
  """

  @doc "A required string argument. Blank counts as missing."
  def require_string(args, key) do
    case string(args, key) do
      nil -> {:error, ~s(Missing required argument "#{key}".)}
      value -> {:ok, value}
    end
  end

  @doc "An optional string argument, or `default`. Blank and whitespace-only become `default`."
  def string(args, key, default \\ nil) do
    case Map.get(args, key) do
      value when is_binary(value) -> if String.trim(value) == "", do: default, else: value
      _ -> default
    end
  end

  @doc "An optional integer, accepting the string form a model often produces."
  def integer(args, key, default) do
    case Map.get(args, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> default
        end

      _ ->
        default
    end
  end

  @doc "An optional boolean, accepting `\"true\"` / `\"false\"`."
  def boolean(args, key, default) do
    case Map.get(args, key) do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _ -> default
    end
  end

  @doc """
  An optional list of strings.

  A bare string is wrapped rather than rejected: models routinely send `"Schützenfest"`
  where `["Schützenfest"]` was asked for, and refusing that helps nobody.
  """
  def string_list(args, key, default \\ nil) do
    case Map.get(args, key) do
      list when is_list(list) -> Enum.filter(list, &is_binary/1)
      value when is_binary(value) -> [value]
      _ -> default
    end
  end

  @doc """
  Builds the attrs map for a changeset from the arguments actually present.

  `fields` maps an argument name to the attribute key. Absent arguments are left out
  entirely, so an update touches only what the caller named — passing `nil` for every
  unmentioned field would blank the record instead.
  """
  def take(args, fields) do
    Enum.reduce(fields, %{}, fn {arg, attr}, acc ->
      if Map.has_key?(args, arg), do: Map.put(acc, attr, Map.get(args, arg)), else: acc
    end)
  end

  @doc """
  Renders changeset errors as one line a model can act on, e.g.
  `slug: kann nicht leer sein; status: ist ungültig`.
  """
  def errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), "") |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end
