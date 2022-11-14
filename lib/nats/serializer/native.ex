defmodule Nats.Serializer.Native do
  @moduledoc false
  @behaviour Nats.Serializer

  @impl true
  def encode(payload, opts \\ [])

  def encode(payload, _opts), do: {:ok, :erlang.term_to_binary(payload)}

  @impl true
  def decode(payload, _opts), do: {:ok, :erlang.binary_to_term(payload)}
end
