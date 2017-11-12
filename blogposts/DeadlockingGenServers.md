I want to describe my first iteration of **exsim**, the core server for
the large scale simulation I described in my last 
[blog post](https://ccpsnorlax.blogspot.is/2017/11/large-scale-ambitions.html).

A **Listener** module opens a socket for listening to incoming connections.
Once a connection is made, a process is spawned for handling the login and
the listener continues listening for new connections.

Once logged in, a **Player** is created, and a **Solarsystem** is started 
(if it hasn't already). The solar system also starts a **PhysicsProxy**, 
and the player starts a **Ship**. These are all GenServer processes.

The source for this is up on GitHub: https://github.com/snorristurluson/exsim

## Player
The player takes ownership of the TCP connection and handles communication
with the game client (or bot). Incoming messages are parsed in *handle_info/2*
and handled by the player or routed to the ship, as appropriate.

The player creates the ship in its *init/1* function.

The state for the player holds the ship and the name of the player.

## Ship
The ship holds the state of the ship - its position, velocity, list of
ships in range, etc. It also accepts commands from the player and queues
them up for sending to the physics simulation.

## PhysicsProxy
The physics proxy manages the connection to the physics simulation, which
is run in a separate OS process. The connection is a TCP socket, and the
communication is done with JSON packets.

## Solarsystem
The solar system holds a list of ships present in the system, plus the
link to the physics proxy.

It manages the ticking of the simulation for the system, which goes
something like this:
1. Save current list of ships as pending ships
1. Call update on each ship
   1. Ship sends physics commands, and notifies system when done
   1. System removes ship from pending list once notification is received
1. Once all ships are updated, the solar system updates the physics simulation
   1. Sends a *stepsimulation* command
   1. Sends a *getstate* command
1. When the physics proxy receives the state from the physics simulation,
it sends it to the solar system
1. The solar system distributes the state:
   1. Sets the state for each ship (position, list of ships in range)
   1. Tells each ship to send the state to its client
      1. Ship gathers state from each ship within range, accumulating into
      a list
      1. Ship encodes the state to JSON and sends to client
      1. Ship notifies solar system that state has been delivered
1. Once all ships have delivered their state, the next tick is scheduled

If I leave out the step of gathering state from each within range, this
seems to work just fine. It is disappointing to see how slow the encoding
and decoding of JSON is - I was hoping to be able to get to some decent
numbers of bots running with this simplistic approach, but with only
a few hundred bots running I'm already spending over a second per tick,
most of it on JSON.

That's fine, I never expected to scale up with a fat text-based protocol
for communication - it was convenient for getting started. Being able to
connect to the server, or directly to the physics server with Telnet and
give it commands and be able to read the output was very useful in the
very first steps. I've started looking into other options, either roll my
own binary protocol or use [flatbuffers](https://google.github.io/flatbuffers/).

## I'm waiting...
What is worse, I'm running into deadlocks with this setup if I let each
ship store its own state.

Here's the code for gathering the state:
```elixir
  def handle_cast({:send_solarsystem_state, solarsystem_state}, state) do
    me = %{"owner" => state[:owner], "type" => state[:typeid], "position" => state[:pos]}
    ships = [me]
    ships = List.foldl(
      state[:in_range],
      ships,
      fn (other, acc) ->
        Logger.info "Finding pid for #{other}"
        other_ship = GenServer.whereis({:global, "ship_#{other}"})
        other_desc = %{
          "owner" => other,
          "type" => Ship.get_typeid(other_ship),
          "position" => Ship.get_position(other_ship)
        }
        List.append(acc, other_desc)
      end)
    {:ok, json} = Poison.encode(%{"state" => %{"ships" => ships}})
    :gen_tcp.send(state[:socket], json)
    Solarsystem.notify_ship_state_delivered(state[:solarsystem], self())
    {:noreply, state}
  end
```
Each ship is its own GenServer process, and the solar system casts this
message to all ships, so they are all running this function concurrently.
This works most of the time, but eventually I get an error like this:
```
23:24:42.472 [error] GenServer "ship_8" terminating
** (stop) exited in: GenServer.call(#PID<0.173.0>, {:get_typeid}, 5000)
    ** (EXIT) time out
    (elixir) lib/gen_server.ex:774: GenServer.call/3
    (solarsystem) lib/ship.ex:140: anonymous fn/2 in Ship.handle_cast/2
    (elixir) lib/list.ex:186: List."-foldl/3-lists^foldl/2-0-"/3
    (solarsystem) lib/ship.ex:132: Ship.handle_cast/2
    (stdlib) gen_server.erl:616: :gen_server.try_dispatch/4
    (stdlib) gen_server.erl:686: :gen_server.handle_msg/6
```
The problem is that *get_typeid/1* and similar functions need a reply
from the GenServer for the ship, but that ship may also be calling
another ship requesting information, and sooner or later I run into
a deadlock, where ship A is waiting for a response from ship B, which
is waiting for a response from ship C, which is waiting for a response
from ship A.

## Dumbing it down
The solution, or at least a solution, is probably to stop storing
state in the Ship process. The state comes from the solar system anyway,
there maybe isn't any need to break it up and have each ship store its
own piece of the information. If I keep all the state in the solar system
and pass it down to the ship, the ship may as well gather the relevant
bits to send to the client from the original big blob of state. Then
this function in the Ship doesn't need to call other ships synchronously
and I should be free from deadlocks. I guess I'm still thinking too much
along the lines of object-oriented programming.

## I must be missing something
I'm a little bit surprised at how easy it was to paint myself into a
corner with Elixir. It's very easy to do certain things very efficiently
with Erlang and Elixir, making good use of concurrency to keep things
going with good performance. 

I need to understand better how to use GenServers, where to store state
and how to prevent deadlocks. The inherent problems of concurrency don't
just disappear, even though the programming language provides
mechanisms and conventions to deal with them. 