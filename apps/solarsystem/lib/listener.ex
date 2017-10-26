require Logger

defmodule Listener do
  @moduledoc false
  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port,
                      [:binary, packet: :line, active: false, reuseaddr: true])
    Logger.info "Accepting connections on port #{port}"
    loop_acceptor(socket, 1)
  end

  defp loop_acceptor(socket, id) do
    {:ok, client} = :gen_tcp.accept(socket)
    Logger.info "Connection established"
    {:ok, player} = Player.start_link(Integer.to_string(id), client)
    {:ok, pid} = Task.Supervisor.start_child(
      Solarsystem.TaskSupervisor,
      fn -> serve(client, player) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket, id + 1)
  end

  defp serve(socket, player) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    Player.handle_data(player, data)
    serve(socket, player)
  end

end