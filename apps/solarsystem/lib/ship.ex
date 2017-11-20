require Logger

defmodule Ship do
  @moduledoc false
  


  use GenServer

  def start_link(owner, typeid, socket) do
    state = %{owner: owner, typeid: typeid, socket: socket}
    name = "ship_#{owner}"
    GenServer.start_link(__MODULE__, state, [{:name, {:global, name}}])
  end

  def find(name) do

  end

  def set_solarsystem(pid, solarsystem) do
    GenServer.call(pid, {:set_solarsystem, solarsystem})
  end

  def get_solarsystem(pid) do
    GenServer.call(pid, {:get_solarsystem})
  end

  def get_position(pid) do
    GenServer.call(pid, {:get_position})
  end

  def set_position(pid, pos) do
    GenServer.call(pid, {:set_position, pos})
  end

  def set_target_location(pid, location) do
    GenServer.cast(pid, {:set_target_location, location})
  end

  def set_in_range(pid, inrange) do
    GenServer.cast(pid, {:set_in_range, inrange})
  end

  def get_owner(pid) do
    GenServer.call(pid, {:get_owner})
  end

  def get_typeid(pid) do
    GenServer.call(pid, {:get_typeid})
  end

  def update(pid) do
    GenServer.cast(pid, {:update})
  end

  def send_solarsystem_state(pid, solarsystem_state) do
    GenServer.cast(pid, {:send_solarsystem_state, solarsystem_state})
  end

  # Server callbacks

  def init(state) do
    Logger.info "Ship init"
    pos = %{ x: :rand.uniform() * 5000 - 2500, y: :rand.uniform() * 5000 - 2500, z: 0}
    state = Map.put(state, :pos, pos)
    state = Map.put(state, :pending_commands, :queue.new())
    {:ok, state}
  end

  def handle_call({:get_position}, _from, state) do
    {:reply, state[:pos], state}
  end

  def handle_call({:set_position, pos}, _from, state) do
    state = Map.put(state, :pos, pos)
    {:reply, :ok, state}
  end

  def handle_call({:set_solarsystem, solarsystem}, _from, state) do
    state = Map.put(state, :solarsystem, solarsystem)
    {:reply, :ok, state}
  end

  def handle_call({:get_solarsystem}, _from, state) do
    {:reply, state[:solarsystem], state}
  end

  def handle_call({:get_owner}, _from, state) do
    {:reply, state[:owner], state}
  end

  def handle_call({:get_typeid}, _from, state) do
    {:reply, state[:typeid], state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast({:set_target_location, location}, state) do
    command = %{
      command: "setshiptargetlocation",
      params: %{
        shipid: state[:owner],
        location: location
      },
    }
    {_, state} = Map.get_and_update(
      state,
      :pending_commands,
      fn current -> {:pending_commands, :queue.in(command, current)} end)
    {:noreply, state}
  end

  def handle_cast({:set_in_range, inrange}, state) do
    IO.inspect(inrange)
    state = Map.put(state, :in_range, inrange)
    {:noreply, state}
  end

  def handle_cast({:update}, state) do
    {commands, state} = Map.get_and_update(
      state,
      :pending_commands,
      fn current -> {current, :queue.new()} end)
    Solarsystem.send_queued_physics_commands(state[:solarsystem], commands)
    Solarsystem.notify_ship_update_done(state[:solarsystem], self())
    {:noreply, state}
  end

  def handle_cast({:send_solarsystem_state, solarsystem_state}, state) do
    all_ships = solarsystem_state["ships"]
    me = all_ships["ship_#{state[:owner]}"]
    case me do
      nil ->
        # Ship didn't exist in the solar system state, can happen on the
        # first tick when a ship is added
        nil
      _ ->
        ships = [me]
        ships = List.foldl(
          me["inrange"],
          ships,
          fn (other, acc) ->
            other_ship = all_ships["ship_#{other}"]
            [other_ship | acc]
          end)
        {:ok, json} = Poison.encode(%{"state" => %{"ships" => ships}})
        :gen_tcp.send(state[:socket], json <> "\n")
    end
    Solarsystem.notify_ship_state_delivered(state[:solarsystem], self())
    {:noreply, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def terminate(reason, state) do
    Logger.info "Terminating ship #{state[:owner]}"
    :normal
  end
end