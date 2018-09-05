defmodule IoT.Simulator.Server do
  @moduledoc """
  Documentation for IoT.Simulator.Server
  """

  require Logger
  use GenServer
  import IoT.Simulator.Util, only: [print_ip_port: 2, convert_data: 1]

  @recv_timeout 500

  alias __MODULE__, as: State
  defstruct [
    ip:       nil,
    port:     nil,
    socket:   nil,
    desirable_temp: nil,
    sensors:  [],
    heaters:  []
  ]

  #----------------------> Client API <--------------------------

  @doc """
  Start server for IoT Simulator.

  ## Examples

      iex> {:ok, pid} = IoT.Simulator.Server.start_link

  """
  def start_link(ip, port) when is_tuple(ip) and is_integer(port) do
    GenServer.start_link(__MODULE__, {ip, port}, name: IoT_Simulator)
  end

  @doc """
  Start listening for incoming connections from sensors and heaters.

  ## Examples

      iex> :ok = IoT.Simulator.Server.listen(ip, port)

  """
  def listen(ip, port) do

    # Socket options
    # 1. :binary          - receives data as binaries (instead of lists)
    # 2. packet: :line    - receives data line by line
    # 3. active: false    - blocks on `:gen_tcp.recv/2` until data is available
    # 4. reuseaddr: true  - allows us to reuse the address if the listener crash

    opts = [:binary, :inet, active: false, ip: ip, reuseaddr: true]
    case :gen_tcp.listen(port, opts) do
      {:ok, listen_socket} ->
        Logger.info "Listening to connections on #{print_ip_port(ip, port)}"
        acceptor(listen_socket)
        {:ok, %State{ip: ip, port: port, socket: listen_socket}}
      {:error, reason} ->
        Logger.error "Could not listen: #{reason}"
        send(self(), :EXIT)
    end
  end

  @doc """
  Set desirable temperature.

  ## Examples

      iex> :ok = IoT.Simulator.Server.set_temperature(22.5)

  """
  def set_temperature(temp) when is_float(temp) do
    GenServer.call(IoT_Simulator, {:set_temperature, temp})
  end

  @doc """
  Get setted temperature.

  ## Examples

      iex> desirable_temp = IoT.Simulator.Server.get_temperature()

  """
  def get_temperature do
    GenServer.call(IoT_Simulator, :get_temperature)
  end

  #-------------------------> GenServer callbacks <---------------------------
  @doc false
  def init {ip, port} do
    Logger.metadata(module: __MODULE__)
    {:ok, %State{ip: ip, port: port}}
  end

  def handle_cast({:sensor, client}, %State{sensors: sensors} = state) do
    sensors = [%{sensor: client, temp: nil} | sensors]
    {:noreply, %State{state | sensors: sensors}}
  end

  def handle_cast({:heater, client}, %State{heaters: heaters} = state) do
    heaters = [%{heater: client, program: nil} | heaters]
    {:noreply, %State{state | heaters: heaters}}
  end

  def handle_cast({:remove, client}, %State{sensors: sensors, heaters: heaters} = state) do
    sensors = Enum.reject(sensors, fn map -> map.sensor == client end)
    heaters = Enum.reject(heaters, fn map -> map.heater == client end)
    {:noreply, %State{state | heaters: heaters, sensors: sensors}}
  end

  def handle_cast({:add_temp, temp, client}, %State{sensors: sensors, heaters: heaters, desirable_temp: desirable_temp} = state) do
    sensors = Enum.map(sensors, fn map -> if (map.sensor == client), do: %{sensor: map.sensor, temp: temp}, else: map end)
    heaters = set_program(sensors, heaters, desirable_temp)
    {:noreply, %State{state | heaters: heaters, sensors: sensors}}
  end

  def handle_call({:set_temperature, temp}, _from, state) do
    {:reply, :ok, %State{ state | desirable_temp: temp}}
  end

  def handle_call(:get_temperature, _from, %State{desirable_temp: desirable_temp} = state) do
    {:reply, desirable_temp, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  #--------------> Privates function to accepting connections and getting data <------------------
  defp acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Logger.info "Accept connection from client #{inspect client}"
    {:ok, pid} = Task.Supervisor.start_child(IoT.Simulator.Server.TaskSupervisor, fn -> client_type(client) end)
    :ok = :gen_tcp.controlling_process(client, pid)
    acceptor(socket)
  end

  defp client_type(client) do
    # recv(Socket, Length, Timeout) - If Length is 0, all available bytes are returned
    case :gen_tcp.recv(client, 0, @recv_timeout) do
      {:ok, data} ->
        case convert_data(data) do
          {:type, :sensor} ->
            Logger.info "Client #{inspect client} type: sensor"
            GenServer.cast(IoT_Simulator, {:sensor, client})
          {:type, :heater} ->
            Logger.info "Client #{inspect client} type: heater"
            GenServer.cast(IoT_Simulator, {:heater, client})
        end
        serve(client)
      {:error, reason} ->
        Logger.warn "Client #{inspect client} terminating: #{inspect reason}"
        GenServer.cast(IoT_Simulator, {:remove, client})
    end
  end

  defp serve(client) do
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        {:temp, temp} = convert_data(data)
        temp = temp |> Atom.to_string |> String.to_float
        Logger.info "Received temperature #{inspect temp} from sensor #{inspect client}"
        GenServer.cast(IoT_Simulator, {:add_temp, temp, client})
        serve(client)
      {:error, reason} ->
        Logger.warn "Client #{inspect client} terminating: #{inspect reason}"
        GenServer.cast(IoT_Simulator, {:remove, client})
    end
  end

  ###########################################################################
  defp set_program(sensors, heaters, desirable_temp) do
    if Enum.all?(sensors, fn map -> map.temp != nil end) do

      current_program = sensors |> avg() |> get_program_info(desirable_temp)
      if Enum.all?(heaters, fn map -> map.program != current_program end) do
        Enum.map(heaters, fn map ->
          :ok = :gen_tcp.send map.heater, "#{current_program}"
          Map.put(map, :program, current_program)
        end)
      else
        heaters
      end

    else
      heaters
    end
  end

  defp avg(list), do: Enum.reduce(list, 0, fn (map, acc) -> map.temp + acc end) / length(list)

  defp get_program_info(current_temp, desirable_temp) do
    cond do
      current_temp >= desirable_temp - 0.5 and current_temp <= desirable_temp + 0.5 -> :keep
      current_temp < desirable_temp - 0.5 -> :heat
      current_temp > desirable_temp + 0.5 -> :off
    end
  end

end
