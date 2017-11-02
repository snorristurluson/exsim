require Logger

defmodule PhysicsProxy do
  @moduledoc false

  use GenServer

  def start_link(name, port) do
    Logger.info "Starting physics for #{name}"
    GenServer.start_link(__MODULE__, {name, port}, [{:name, {:global, "physics_" <> name}}])
  end

  def send_command(pid, json) do
    GenServer.call(pid, {:send_command, json})
  end

  def init({name, port}) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, {:packet, 0}])
    Logger.info "Connected on port #{port}"
    {:ok, %{name: name, socket: socket}}
  end

  def handle_call({:send_command, json}, _from, state) do
    Logger.info "Send: #{json}"
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
    Logger.info "Received: #{data}"
    {:noreply, state}
  end

  def handle_info({port, {:data, data}}, %{port: port, name: name}=state) do
    Logger.info "#{name}: #{data}"
    {:noreply, state}
  end

end