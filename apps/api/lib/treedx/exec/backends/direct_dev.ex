defmodule TreeDx.Exec.Backends.DirectDev do
  @moduledoc false

  def run(command, cwd, timeout_ms, max_output_bytes, opts \\ %{}) do
    run_dir =
      Path.join([
        TreeDx.Store.data_dir(),
        "tmp",
        "exec",
        System.unique_integer([:positive]) |> Integer.to_string()
      ])

    try do
      with {:ok, shell} <- shell_executable(),
           {:ok, timeout} <- timeout_executable() do
        File.mkdir_p!(run_dir)

        command_file = Path.join(run_dir, "command.sh")
        wrapper_file = Path.join(run_dir, "runner.sh")
        stdout_file = Path.join(run_dir, "stdout")
        stderr_file = Path.join(run_dir, "stderr")
        File.write!(command_file, command)

        File.write!(wrapper_file, """
        cd #{shell_quote(cwd)}
        env -i PATH=#{shell_quote(System.get_env("PATH") || "/usr/bin:/bin")} HOME=#{shell_quote(cwd)} LANG=C.UTF-8 #{shell_quote(shell)} #{shell_quote(command_file)} > #{shell_quote(stdout_file)} 2> #{shell_quote(stderr_file)}
        """)

        {_, exit_code} =
          System.cmd(
            timeout.command,
            timeout.args ++ [timeout_arg(timeout_ms), shell, wrapper_file]
          )

        stdout = File.read(stdout_file) |> elem_or_empty()
        stderr = File.read(stderr_file) |> elem_or_empty()
        timed_out = exit_code == 124
        stderr = if timed_out and stderr == "", do: "Command timed out.", else: stderr
        {stdout, stderr, truncated} = cap_output(stdout, stderr, max_output_bytes)

        {:ok,
         %{
           exit_code: exit_code,
           stdout: sanitize(stdout),
           stderr: sanitize(stderr),
           truncated: truncated,
           sandbox: %{
             backend: "direct_dev",
             network: "host",
             resourceLimits: TreeDx.Exec.Backend.resource_limits(opts),
             isolated: false
           }
         }}
      end
    after
      File.rm_rf(run_dir)
    end
  end

  defp shell_executable do
    cond do
      executable = System.find_executable("bash") -> {:ok, executable}
      executable = System.find_executable("sh") -> {:ok, executable}
      true -> unavailable("shell executable is not available.")
    end
  end

  defp timeout_executable do
    cond do
      executable = System.find_executable("timeout") ->
        {:ok, %{command: executable, args: []}}

      File.exists?("/bin/busybox") ->
        {:ok, %{command: "/bin/busybox", args: ["timeout"]}}

      true ->
        unavailable("timeout executable is not available.")
    end
  end

  defp unavailable(message),
    do:
      {:error,
       %{
         code: "sandbox_unavailable",
         message: "direct_dev exec backend is unavailable: #{message}"
       }}

  defp timeout_arg(timeout_ms), do: "#{max(div(timeout_ms + 999, 1000), 1)}s"

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

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
end
