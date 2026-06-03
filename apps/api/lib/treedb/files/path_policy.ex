defmodule TreeDb.Files.PathPolicy do
  @moduledoc false

  @protected_roots ~w(.git .ssh node_modules dist target _build deps .elixir_ls)
  @protected_names ~w(package-lock.json pnpm-lock.yaml yarn.lock Cargo.lock mix.lock poetry.lock Gemfile.lock id_rsa)

  def normalize(path, opts \\ []) do
    allow_empty = Keyword.get(opts, :allow_empty, false)
    path = path || ""

    cond do
      !is_binary(path) ->
        {:error, error("validation_error", "path must be a string.")}

      String.contains?(path, <<0>>) ->
        {:error, error("validation_error", "path must not contain NUL bytes.")}

      String.starts_with?(path, "/") ->
        {:error, error("validation_error", "path must be repository-relative.")}

      String.contains?(path, "\\") ->
        {:error, error("validation_error", "path must use POSIX separators.")}

      encoded_traversal?(path) ->
        {:error, error("validation_error", "path traversal is not allowed.")}

      true ->
        parts =
          path
          |> String.split("/", trim: true)

        if Enum.any?(parts, &(&1 == "..")) do
          {:error, error("validation_error", "path traversal is not allowed.")}
        else
          normalized = Enum.join(parts, "/")

          if normalized == "" and !allow_empty do
            {:error, error("validation_error", "path is required.")}
          else
            {:ok, normalized}
          end
        end
    end
  end

  def authorize(workspace, path, allow_protected) do
    with :ok <- scope_allowed(workspace, path),
         :ok <- protected_allowed(path, allow_protected) do
      :ok
    end
  end

  def protected?(path) do
    parts = String.split(path || "", "/", trim: true)
    name = List.last(parts) || ""

    cond do
      Enum.any?(parts, &(&1 in @protected_roots)) -> true
      name in @protected_names -> true
      name == ".env" or String.starts_with?(name, ".env.") -> true
      String.ends_with?(name, ".pem") or String.ends_with?(name, ".key") -> true
      true -> false
    end
  end

  defp scope_allowed(_workspace, ""), do: :ok

  defp scope_allowed(workspace, path) do
    TreeDb.Capabilities.require_paths(workspace["effectiveScope"] || %{}, [path])
  end

  defp protected_allowed(_path, true), do: :ok

  defp protected_allowed(path, _allow_protected) do
    if protected?(path) do
      {:error,
       %{
         code: "permission_denied",
         message: "Permission denied.",
         details: %{path: path, protected: true}
       }}
    else
      :ok
    end
  end

  defp error(code, message), do: %{code: code, message: message}

  defp encoded_traversal?(path) do
    path
    |> String.downcase()
    |> String.replace("%2e", ".")
    |> String.split("/", trim: true)
    |> Enum.any?(&(&1 == ".."))
  end
end
