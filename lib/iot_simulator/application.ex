defmodule IoT.Simulator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do

    ip = Application.get_env :iot_simulator, :ip
    port = Application.get_env :iot_simulator, :port

    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: IoT.Simulator.Server.Worker.start_link(arg)
      # {IoT.Simulator.Server.Worker, arg},
      {Task.Supervisor, name: IoT.Simulator.Server.TaskSupervisor},
      {Task, fn ->
        {:ok, _pid} = IoT.Simulator.Server.start_link(ip, port)
        :ok = IoT.Simulator.Server.listen(ip, port)
      end}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: IoT.Simulator.Server.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
