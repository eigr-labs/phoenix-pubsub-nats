defmodule Nats.Serializer.Json do
  @moduledoc false
  @behaviour Nats.Serializer

  @impl true
  def encode(payload, opts \\ [])

  def encode(payload, _opts), do: Jason.encode(payload)

  @impl true
  def decode(payload, _opts), do: Jason.decode(payload)
end
