defmodule Nats.Consumer do
  @moduledoc """
  Node subscriber
  """
  use Gnat.Server
  require Logger

  def request(
        %{
          body: body,
          headers: headers,
          topic: topic
        } = event
      ) do
    Logger.debug("Received request #{inspect(event)}")
    current_node = to_string(node())

    with {:convert_headers, %{"serializer_type" => serializer_type} = headers} <-
           {:convert_headers, conver_headers_to_map(headers)},
         {:decode,
          %{
            name: name,
            dispatcher: dispatcher,
            from: from,
            payload: message,
            pubsub_name: _pubsub_name
          }} <- {:decode, decode(serializer_type, body)} do
      target = get_target(headers)
      real_topic = get_real_topic(topic)

      cond do
        from == current_node ->
          # This node is the source, nothing to do, because local dispatch already
          # happened.
          :ok

        not is_nil(target) and target != current_node ->
          #   when not is_nil(target) and target != current_node ->
          # Direct broadcast and this is not the destination node.
          :ok

        true ->
          res =
            Phoenix.PubSub.local_broadcast(
              name,
              real_topic,
              message,
              maybe_convert_to_existing_atom(dispatcher)
            )

          res
      end
    else
      {:convert_headers, msg} ->
        Logger.warning("Unable to parse headers. Details: #{inspect(msg)}")
        :ok

      {:decode, msg} ->
        Logger.warning("Unable to decode the message. Details: #{inspect(msg)}")
        :ok

      error ->
        Logger.warning("Unable to process pubsub message. Details: #{inspect(error)}")
        :ok
    end
  end

  def error(%{gnat: _gnat, reply_to: _reply_to}, error) do
    Logger.error(
      "Error on #{inspect(__MODULE__)} during handle incoming message. Error  #{inspect(error)}"
    )
  end

  defp decode(serializer_type, body) do
    serializer =
      case serializer_type do
        "json" ->
          Nats.Serializer.Json

        _ ->
          Nats.Serializer.Native
      end

    case serializer.decode(body, []) do
      {:ok, payload} ->
        payload

      _ ->
        raise ArgumentError, "Could not deserialize data: #{inspect(body)}"
    end
  end

  defp get_target(headers) do
    if Map.has_key?(headers, "target") do
      Map.get(headers, "target", nil)
    else
      nil
    end
  end

  defp get_real_topic(topic) do
    String.replace(topic, "nodes.pubsub.", "")
  end

  defp conver_headers_to_map(headers), do: Enum.into(headers, %{})

  defp maybe_convert_to_existing_atom(string) when is_binary(string),
    do: String.to_existing_atom(string)

  defp maybe_convert_to_existing_atom(atom) when is_atom(atom), do: atom
end
