defmodule Bbh.Notifications.PushSubscription do
  @moduledoc "A browser Web Push subscription."
  use Bbh.Schema

  @categories ~w(termine news)
  def categories, do: @categories

  @label_max 40
  def label_max, do: @label_max

  schema "push_subscriptions" do
    field :endpoint, :string
    field :keys_p256dh, :string
    field :keys_auth, :string
    field :categories, {:array, :string}, default: []
    field :last_used, :utc_datetime
    # Consecutive non-fatal send failures (reset on success) + when the last one was.
    # System-managed (see Bbh.Notifications.do_send/2), so not cast from params.
    field :error_count, :integer, default: 0
    field :last_error_at, :utc_datetime
    # Test receiver for admin trial sends. Set only through
    # `Bbh.Notifications.set_tester/2` (admin route), so not cast from params.
    field :tester, :boolean, default: false
    # Browser/OS summary from the subscribe request (`Bbh.Notifications.Device`).
    # System-managed, so not cast from params.
    field :device, :string
    # Name an admin gives the device from the device itself. Set only through
    # `Bbh.Notifications.set_label/2` (admin route), so not cast from params.
    field :label, :string

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
