defmodule TreeDb.Exec.Backends.DirectDev do
  @moduledoc false

  def run(command, cwd, timeout_ms, max_output_bytes, opts \\ %{}) do
    run_dir =
      Path.join([
        TreeDb.Store.data_dir(),
        "tmp",
        "exec",
        System.unique_integer([:positive]) |> Integer.to_string()
      ])

    try do
      File.mkdir_p!(run_dir)

      command_file = Path.join(run_dir, "command.sh")
      wrapper_file = Path.join(run_dir, "runner.sh")
      stdout_file = Path.join(run_dir, "stdout")
      stderr_file = Path.join(run_dir, "stderr")
      File.write!(command_file, command)

      File.write!(wrapper_file, """
      cd #{shell_quote(cwd)}
      env -i PATH=#{shell_quote(System.get_env("PATH") || "/usr/bin:/bin")} HOME=#{shell_quote(cwd)} LANG=C.UTF-8 bash #{shell_quote(command_file)} > #{shell_quote(stdout_file)} 2> #{shell_quote(stderr_file)}
      """)

      {_, exit_code} = System.cmd("timeout", [timeout_arg(timeout_ms), "bash", wrapper_file])
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
           resourceLimits: TreeDb.Exec.Backend.resource_limits(opts),
           isolated: false
         }
       }}
    after
      File.rm_rf(run_dir)
    end
  end

  defp timeout_arg(timeout_ms), do: "#{max(timeout_ms, 1) / 1000}s"

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
