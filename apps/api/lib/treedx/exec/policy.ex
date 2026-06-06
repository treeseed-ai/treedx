defmodule TreeDx.Exec.Policy do
  @moduledoc false

  @read_only_commands ~w(ls pwd cat head tail find grep rg)
  @verification_prefixes [
    "npm test",
    "npm run test",
    "npm run typecheck",
    "npm run build",
    "pnpm test",
    "pnpm build"
  ]
  @blocked_git ~r/\bgit\s+(push|merge|rebase|commit|reset|checkout|switch|branch|tag)\b/
  @escape_tokens ["..", "$(", "`", "&&", "||", ";", "<"]
  @write_tokens [">", ">>", " 2>", "| tee "]

  def profile("verification"), do: "verification"
  def profile("write_limited"), do: "write_limited"
  def profile(_), do: "read_only_basic"

  def allow(command, mode) when is_binary(command) do
    command = String.trim(command)

    cond do
      command == "" ->
        deny("cmd is required.")

      Regex.match?(@blocked_git, command) ->
        deny("shell Git mutation commands are not allowed.")

      Enum.any?(@escape_tokens, &String.contains?(command, &1)) ->
        deny("command contains disallowed shell syntax.")

      mode == "read_only" ->
        allow_read_only(command)

      mode == "verification" ->
        allow_verification(command)

      mode == "write_limited" ->
        allow_write_limited(command)

      true ->
        deny("unsupported exec mode.")
    end
  end

  def allow(_command, _mode), do: deny("cmd is required.")

  defp allow_read_only(command) do
    cond do
      Enum.any?(@write_tokens, &String.contains?(command, &1)) ->
        deny("read-only exec cannot use write shell syntax.")

      allowed_pipeline?(command) ->
        :ok

      true ->
        deny("command is not in the read-only allowlist.")
    end
  end

  defp allow_verification(command) do
    verification_command? =
      Enum.any?(
        @verification_prefixes,
        &(command == &1 or String.starts_with?(command, &1 <> " "))
      )

    cond do
      verification_command? ->
        :ok

      allow_read_only(command) == :ok ->
        :ok

      true ->
        deny("command is not in the verification allowlist.")
    end
  end

  defp allow_write_limited(command) do
    cond do
      String.starts_with?(command, "/") ->
        deny("absolute command paths are not allowed.")

      Regex.match?(~r/(^|\s)(sudo|su|ssh|scp|curl|wget|nc|ncat)\b/, command) ->
        deny("command is not allowed in write-limited mode.")

      true ->
        :ok
    end
  end

  defp allowed_pipeline?(command) do
    command
    |> String.split("|")
    |> Enum.all?(&allowed_read_segment?/1)
  end

  defp allowed_read_segment?(segment) do
    args = segment |> String.trim() |> String.split(~r/\s+/, trim: true)
    command = List.first(args)

    cond do
      command in @read_only_commands ->
        command != "sed" or Enum.at(args, 1) == "-n"

      command == "sed" ->
        Enum.at(args, 1) == "-n"

      command == "git" ->
        Enum.at(args, 1) in ["status", "diff", "log", "show"]

      true ->
        false
    end
  end

  defp deny(message), do: {:error, %{code: "permission_denied", message: message}}
end
