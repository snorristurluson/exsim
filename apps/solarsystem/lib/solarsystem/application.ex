defmodule Solarsystem.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {Task.Supervisor, name: Solarsystem.TaskSupervisor},
      {Task, fn -> Listener.accept(4040) end},
      %{id: "ex1", start: {Solarsystem, :start, ["ex1"]}}
    ]

    opts = [strategy: :one_for_one, name: Solarsystem.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
