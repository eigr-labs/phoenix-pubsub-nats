defmodule NatsProxy do
  @moduledoc """
  A TCP proxy in front of the NATS server, so a test can cut the adapter's
  connections as a NATS restart or a network failure would.

  `drop/0` closes every proxied connection. `refuse/1` makes new connections
  close as soon as they are accepted, so NATS looks unreachable until
  `refuse(false)`.
  """
  use GenServer

  def start_link(upstream_port) do
    GenServer.start_link(__MODULE__, upstream_port, name: __MODULE__)
  end

  def port, do: GenServer.call(__MODULE__, :port)

  def upstream_port, do: GenServer.call(__MODULE__, :upstream_port)

  def drop, do: GenServer.call(__MODULE__, :drop)

  def refuse(refuse?), do: GenServer.call(__MODULE__, {:refuse, refuse?})

  @impl true
  def init(upstream_port) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listener)
    proxy = self()
    spawn_link(fn -> accept(listener, proxy, upstream_port) end)
    {:ok, %{port: port, upstream_port: upstream_port, connections: [], refuse?: false}}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call(:upstream_port, _from, state), do: {:reply, state.upstream_port, state}

  def handle_call(:drop, _from, state) do
    Enum.each(state.connections, &send(&1, :drop))
    {:reply, :ok, %{state | connections: []}}
  end

  def handle_call({:refuse, refuse?}, _from, state),
    do: {:reply, :ok, %{state | refuse?: refuse?}}

  def handle_call(:accept?, _from, state), do: {:reply, not state.refuse?, state}

  def handle_call({:accepted, connection}, _from, state) do
    Process.monitor(connection)
    {:reply, :ok, %{state | connections: [connection | state.connections]}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, connection, _reason}, state),
    do: {:noreply, %{state | connections: List.delete(state.connections, connection)}}

  defp accept(listener, proxy, upstream_port) do
    {:ok, client} = :gen_tcp.accept(listener)

    if GenServer.call(proxy, :accept?) do
      connection = spawn(fn -> forward(client, upstream_port) end)
      :ok = :gen_tcp.controlling_process(client, connection)
      send(connection, :go)
      GenServer.call(proxy, {:accepted, connection})
    else
      :gen_tcp.close(client)
    end

    accept(listener, proxy, upstream_port)
  end

  defp forward(client, upstream_port) do
    receive do
      :go -> :ok
    end

    {:ok, upstream} = :gen_tcp.connect({127, 0, 0, 1}, upstream_port, [:binary, active: true])
    :ok = :inet.setopts(client, active: true)
    pump(client, upstream)
  end

  defp pump(client, upstream) do
    receive do
      {:tcp, ^client, data} ->
        :ok = :gen_tcp.send(upstream, data)
        pump(client, upstream)

      {:tcp, ^upstream, data} ->
        :ok = :gen_tcp.send(client, data)
        pump(client, upstream)

      _closed_or_drop ->
        :gen_tcp.close(client)
        :gen_tcp.close(upstream)
    end
  end
end
