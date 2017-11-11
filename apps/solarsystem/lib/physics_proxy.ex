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
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :line]) do
      {:ok, socket} ->
        :inet.setopts(socket, [{:recbuf, 128*1024}, {:packet_size, 128*1024}])
        Logger.info "Connected on port #{port}"

        {:ok, json} = Poison.encode(%{command: "setmain"})
        json = json <> "\n"
        :gen_tcp.send(socket, json)

        {:ok, %{solarsystem: solarsystem, socket: socket}}
      {:error, reason} ->
        Logger.info "Can't connect to physics server: #{reason}"
        {:ignore, "Can't connect to physics server"}
    end
  end

  def handle_call({:send_command, command}, _from, state) do
    {:ok, json} = Poison.encode(command)
    :gen_tcp.send(state[:socket], json <> "\n")
    {:reply, :ok, state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info({:tcp, socket, data}, state) do
    json = try do
      Poison.decode!(data)
    rescue
      _ -> "error"
    end
    case json do
      %{"state" => solarsystem_state} -> Solarsystem.distribute_state(state[:solarsystem], solarsystem_state)
      _ -> :ok
    end
    {:noreply, state}
  end
end