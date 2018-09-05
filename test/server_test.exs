defmodule IoTSimulator.ServerTest do
  use ExUnit.Case

  setup_all do
    desired_temp = 22.0
    assert :ok = IoT.Simulator.Server.set_temperature(22.0)
    assert ^desired_temp = IoT.Simulator.Server.get_temperature
    {:ok, desired_temp: desired_temp}
  end

  test "sensor__S01", state do
    assert {:ok, pid_sensor01} = IoT.Simulator.Sensor.start_link
    assert {:ok, pid_sensor02} = IoT.Simulator.Sensor.start_link
    assert {:ok, pid_heater01} = IoT.Simulator.Heater.start_link
    assert {:ok, pid_heater02} = IoT.Simulator.Heater.start_link
    :timer.sleep(10) #ms
    assert :ok = IoT.Simulator.Sensor.send_temperature(pid_sensor01, 21.5)
    assert :ok = IoT.Simulator.Sensor.send_temperature(pid_sensor02, 22.5)
    :timer.sleep(50)

    assert :ok = IoT.Simulator.Sensor.send_temperature(pid_sensor01, 23.5)
    :timer.sleep(50)
  end

end
