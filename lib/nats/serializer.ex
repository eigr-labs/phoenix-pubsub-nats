defmodule Nats.Serializer do
  @type payload :: term()
  @type opts :: Keyword.t()

  @callback encode(payload(), opts()) :: {:ok, term()} | {:error, any()}
  @callback decode(payload(), opts()) :: {:ok, term()} | {:error, any()}
end
