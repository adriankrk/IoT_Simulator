defmodule IoT.Simulator.Util do
  @moduledoc false

  def print_ip_port(addr, port), do: "#{s_ip(addr)}:#{port}"
  defp s_ip({a,b,c,d}), do: "#{a}.#{b}.#{c}.#{d}"

  def reconnect(0), do: send(self(), :connect)
  def reconnect(delay), do: Process.send_after(self(), :connect, delay)

  def convert_data({type, data}) do
    to_string(type) <> " " <> to_string(data)
  end

  def convert_data(data) when is_binary(data) do
    data_list = String.split(data, " ")
    cond do
      is_nil(Enum.at(data_list, 0)) or is_nil(Enum.at(data_list, 1)) ->
        {:error, :badarg}
      true ->
        {String.to_atom(Enum.at(data_list, 0)), String.to_atom(Enum.at(data_list, 1))}
    end
  end

end
