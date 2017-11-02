require Logger

defmodule Ship do
  @moduledoc false
  


  use GenServer

  def start_link(owner, typeid) do
    state = %{owner: owner, typeid: typeid}
    GenServer.start_link(__MODULE__, state, [])
  end

  def get_position(pid) do
    GenServer.call(pid, {:get_position})
  end

  def set_position(pid, pos) do
    GenServer.call(pid, {:set_position, pos})
  end

  def get_typeid(pid) do
    GenServer.call(pid, {:get_typeid})
  end

  # Server callbacks

  def init(state) do
    Logger.info "Ship init"
    pos = {:rand.uniform() * 800, :rand.uniform() * 600, 0}
    state = Map.put(state, :pos, pos)
    {:ok, state}
  end

  def handle_call({:get_position}, _from, state) do
    {:reply, state[:pos], state}
  end

  def handle_call({:set_position, pos}, _from, state) do
    state = Map.put(state, :pos, pos)
    {:reply, :ok, state}
  end

  def handle_call({:get_typeid}, _from, state) do
    {:reply, state[:typeid], state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end
end