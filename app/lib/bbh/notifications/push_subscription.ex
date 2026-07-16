defmodule Bbh.Notifications.PushSubscription do
  @moduledoc "A browser Web Push subscription."
  use Bbh.Schema

  @categories ~w(termine news)
  def categories, do: @categories

  schema "push_subscriptions" do
    field :endpoint, :string
    field :keys_p256dh, :string
    field :keys_auth, :string
    field :categories, {:array, :string}, default: []
    field :last_used, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:endpoint, :keys_p256dh, :keys_auth, :categories, :last_used])
    |> validate_required([:endpoint, :keys_p256dh, :keys_auth])
    |> validate_subset(:categories, @categories)
    |> unique_constraint(:endpoint)
  end
end
