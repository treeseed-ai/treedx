defmodule TreeDbProfiler.SystemProfile do
  @moduledoc false

  def collect do
    %{
      "os" => :os.type() |> Tuple.to_list() |> Enum.join("-"),
      "arch" => :erlang.system_info(:system_architecture) |> to_string(),
      "cpuCount" => System.schedulers_online(),
      "memoryBytes" => memory_bytes(),
      "docker" => docker()
    }
  end

  defp memory_bytes do
    case File.read("/proc/meminfo") do
      {:ok, text} ->
        case Regex.run(~r/^MemTotal:\s+(\d+)\s+kB/m, text) do
          [_, kb] -> String.to_integer(kb) * 1024
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp docker do
    try do
      case System.cmd("docker", ["version", "--format", "{{.Server.Version}}"],
             stderr_to_stdout: true
           ) do
        {version, 0} -> %{"available" => true, "version" => String.trim(version)}
        _ -> %{"available" => false}
      end
    rescue
      ErlangError -> %{"available" => false}
    end
  end
end
