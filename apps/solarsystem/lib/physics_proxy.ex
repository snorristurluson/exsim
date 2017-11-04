require Logger

defmodule PhysicsProxy do
  @moduledoc false

  use GenServer

  def start_link(solarsystem, name, port) do
    GenServer.start_link(__MODULE__, {solarsystem, port}, [{:name, {:global, "physics_" <> name}}])
  end

  def send_command(pid, json) do
    GenServer.call(pid, {:send_command, json})
  end

  def init({solarsystem, port}) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, {:packet, 0}])
    Logger.info "Connected on port #{port}"

    {:ok, json} = Poison.encode(%{command: "setmain"})
    :gen_tcp.send(socket, json)

    {:ok, %{solarsystem: solarsystem, socket: socket}}
  end

  def handle_call({:send_command, command}, _from, state) do
    {:ok, json} = Poison.encode(command)
    :gen_tcp.send(state[:socket], json)
    {:reply, :ok, state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info({:tcp, socket, data}, state) do
    lines = String.split(data, "\n")
    Enum.each(lines, fn x -> handle_item(x, state) end)
    {:noreply, state}
  end

  defp handle_item(item, state) do
    Logger.info "Received: #{item}"
    json = try do
      decoded = Poison.decode!(item)
      Logger.info "Decoded json"
      decoded
    rescue
      _ -> "error"
    end
    IO.inspect(json)
    case json do
      %{"state" => solarsystem_state} -> Solarsystem.distribute_state(state[:solarsystem], solarsystem_state)
      _ -> :ok
    end
  end
end