defmodule IoT.Simulator.Sensor do
  @moduledoc """
  Documentation for IoT.Simulator.Sensor
  """

  use GenServer
  require Logger
  import IoT.Simulator.Util, only: [print_ip_port: 2, reconnect: 1, convert_data: 1]

  @conn_timeout 500

  alias __MODULE__, as: State
  defstruct [
    ip:       nil,
    port:     nil,
    socket:   nil,
  ]

  @doc """
  Start simulate sensor for IoT Simulator.

  ## Examples

      iex> {:ok, pid_sensor} = IoT.Simulator.Sensor.start_link

  """
  def start_link() do
    ip = Application.get_env :iot_simulator, :ip
    port = Application.get_env :iot_simulator, :port
    GenServer.start_link(__MODULE__, [ip, port], [])
  end

  @doc """
  Report measured temperature to server, first argument must be a pid of sensor returned from start_link() function.

  ## Examples

      iex> :ok = IoT.Simulator.Sensor.send_temperature(pid_sensor, 22.0)

  """
  def send_temperature(pid, temp) when is_float(temp) and is_pid(pid) do
    GenServer.call(pid, {:send_temperature, temp})
  end

  @doc """
  This function finish simulate a sensor, argument must be a pid of sensor returned from start_link() function.

  ## Examples

      iex> :ok = IoT.Simulator.Sensor.close(pid_sensor)

  """
  def close(pid) when is_pid(pid) do
    GenServer.call(pid, :close)
  end

  #----------------> GenServer callbacks <----------------------
  @doc false
  def init [ip, port] do
    reconnect(0)
    {:ok, %State{ip: ip, port: port}}
  end

  def handle_call({:send_temperature, temp}, {_pid, _tag} = _from, %State{socket: socket} = state) do
    result = socket && :gen_tcp.send(socket, convert_data({:temp, temp}))
    {:reply, result, state}
  end

  def handle_call(:close, _from, %State{socket: socket} = state) do
    result = :gen_tcp.close(socket)
    Logger.info "Socket has been closed"
    {:reply, result, state}
  end

  def handle_info(:connect, state) do
    %State{socket: socket, ip: addr, port: port} = state
    if socket do
      {:noreply, state}
    else
      case :gen_tcp.connect(addr, port, [:binary, :inet, {:active, true}], @conn_timeout) do
        {:ok, socket} ->
          Logger.info "Established connection to server on #{print_ip_port(addr, port)}"
          :ok = :gen_tcp.send(socket, convert_data({:type, :sensor}))
          {:noreply, %State{state | socket: socket}}
        {:error, reason} ->
          Logger.warn "Connection to server on #{print_ip_port(addr, port)} failed (#{inspect reason})"
          reconnect(2000)
          {:noreply, state}
      end
    end
  end

  def handle_info({:tcp, _socket, packet}, state) do
    Logger.info "Incoming packet from server: #{inspect packet}"
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info "Socket has been closed"
    {:noreply, %State{state | socket: nil}}
  end

  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.error "Socket: #{inspect socket} - connection closed due to #{inspect reason}"
    :gen_tcp.close(socket)
    reconnect(0)
    {:noreply, %State{state | socket: nil}}
  end

  def handle_info({:EXIT, from, reason}, state) do
    Logger.error "Failure #{inspect from} #{inspect reason}"
    {:stop, :normal, state}
  end

end
