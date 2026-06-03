defmodule TreeDb.Exec.Backends.ContainerSandbox do
  @moduledoc false

  def run(command, cwd, timeout_ms, max_output_bytes, opts \\ %{}) do
    with docker when is_binary(docker) <- System.find_executable("docker"),
         {:ok, network} <- TreeDb.Exec.Backend.network(opts) do
      run_dir = Path.join([TreeDb.Store.data_dir(), "tmp", "exec", unique_id()])
      File.mkdir_p!(run_dir)
      command_file = Path.join(run_dir, "command.sh")
      stdout_file = Path.join(run_dir, "stdout")
      stderr_file = Path.join(run_dir, "stderr")
      File.write!(command_file, command)

      try do
        {args, sandbox} = docker_args(cwd, run_dir, command_file, timeout_ms, network, opts)

        {_, exit_code} =
          System.cmd(docker, args, stderr_to_stdout: false, into: File.stream!(stdout_file))

        stdout = File.read(stdout_file) |> elem_or_empty()
        stderr = File.read(stderr_file) |> elem_or_empty()
        {stdout, stderr, truncated} = cap_output(stdout, stderr, max_output_bytes)

        {:ok,
         %{
           exit_code: exit_code,
           stdout: sanitize(stdout),
           stderr: sanitize(stderr),
           truncated: truncated,
           sandbox: sandbox
         }}
      after
        File.rm_rf(run_dir)
      end
    else
      nil -> {:error, %{code: "sandbox_unavailable", message: "Docker executable was not found."}}
      {:error, error} -> {:error, error}
    end
  end

  def docker_args(cwd, run_dir, command_file, timeout_ms, network, opts) do
    limits = TreeDb.Exec.Backend.resource_limits(opts)
    image = System.get_env("TREEDB_EXEC_CONTAINER_IMAGE") || "alpine:3.20"

    args = [
      "run",
      "--rm",
      "--network",
      network,
      "--read-only",
      "--cpus",
      to_string(limits.cpu),
      "--memory",
      "#{limits.memoryMb}m",
      "--pids-limit",
      to_string(limits.pids),
      "-v",
      "#{cwd}:/workspace:rw",
      "-v",
      "#{run_dir}:/treedb-exec:rw",
      "-w",
      "/workspace",
      "-e",
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      image,
      "sh",
      "-lc",
      "timeout #{timeout_seconds(timeout_ms)} sh /treedb-exec/#{Path.basename(command_file)} > /treedb-exec/stdout 2> /treedb-exec/stderr"
    ]

    sandbox = %{
      backend: "container_sandbox",
      network: network,
      resourceLimits: limits,
      isolated: true
    }

    {args, sandbox}
  end

  defp unique_id, do: System.unique_integer([:positive]) |> Integer.to_string()
  defp timeout_seconds(timeout_ms), do: max(div(timeout_ms, 1000), 1)
  defp elem_or_empty({:ok, value}), do: value
  defp elem_or_empty(_), do: ""

  defp cap_output(stdout, stderr, max_output_bytes) do
    combined = byte_size(stdout) + byte_size(stderr)

    if combined <= max_output_bytes do
      {stdout, stderr, false}
    else
      stdout_budget = min(byte_size(stdout), max_output_bytes)
      stderr_budget = max(max_output_bytes - stdout_budget, 0)
      {binary_part(stdout, 0, stdout_budget), binary_part(stderr, 0, stderr_budget), true}
    end
  end

  defp sanitize(value) do
    if String.valid?(value) do
      value
    else
      value
      |> :binary.bin_to_list()
      |> Enum.map(fn byte -> if byte in 9..13 or byte in 32..126, do: byte, else: ?? end)
      |> List.to_string()
    end
  end
end
