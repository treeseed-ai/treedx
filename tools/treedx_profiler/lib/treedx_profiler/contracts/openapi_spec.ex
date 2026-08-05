defmodule TreeDxProfiler.OpenApiSpec do
  @moduledoc false

  def load do
    with {:ok, path} <- path(),
         {:ok, spec} <- cached_yaml(path) do
      {:ok, spec}
    end
  end

  def load! do
    case load() do
      {:ok, spec} -> spec
      {:error, message} -> raise message
    end
  end

  def operation(operation_id) do
    with {:ok, path} <- path(),
         {:ok, spec} <- cached_yaml(path) do
      stat = File.stat!(path)
      key = {__MODULE__, :operations, path, stat.mtime, stat.size}

      operations =
        case :persistent_term.get(key, :missing) do
          :missing ->
            indexed = index_operations(spec)
            :persistent_term.put(key, indexed)
            indexed

          indexed ->
            indexed
        end

      case Map.fetch(operations, operation_id) do
        {:ok, operation} -> {:ok, operation}
        :error -> {:error, "operation #{operation_id} not found in OpenAPI"}
      end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp path do
    env_path = System.get_env("TREEDX_OPENAPI_PATH")

    candidates =
      [
        env_path,
        Path.expand("docs/api/openapi.yaml", File.cwd!()),
        Path.expand("../../docs/api/openapi.yaml", File.cwd!()),
        Path.expand("../../../docs/api/openapi.yaml", __DIR__)
      ]
      |> Enum.reject(&is_nil/1)

    case Enum.find(candidates, &File.exists?/1) do
      nil -> {:error, "docs/api/openapi.yaml not found"}
      path -> {:ok, path}
    end
  end

  defp read_yaml(path) do
    spec =
      path
      |> File.read!()
      |> String.to_charlist()
      |> :yamerl_constr.string()
      |> case do
        [doc] -> normalize_yaml(doc)
        [] -> %{}
      end

    {:ok, spec}
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, inspect(reason)}
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp cached_yaml(path) do
    stat = File.stat!(path)
    key = {__MODULE__, path, stat.mtime, stat.size}

    case :persistent_term.get(key, :missing) do
      :missing ->
        with {:ok, spec} <- read_yaml(path) do
          :persistent_term.put(key, spec)
          {:ok, spec}
        end

      spec ->
        {:ok, spec}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp normalize_yaml(value) when is_list(value) do
    cond do
      List.ascii_printable?(value) ->
        to_string(value)

      Keyword.keyword?(value) or Enum.all?(value, &match?({_, _}, &1)) ->
        Map.new(value, fn {key, val} -> {to_string_key(key), normalize_yaml(val)} end)

      true ->
        Enum.map(value, &normalize_yaml/1)
    end
  end

  defp normalize_yaml(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string_key(key), normalize_yaml(val)} end)
  end

  defp normalize_yaml(value) when is_binary(value), do: value
  defp normalize_yaml(value) when is_boolean(value), do: value
  defp normalize_yaml(nil), do: nil
  defp normalize_yaml(:null), do: nil
  defp normalize_yaml(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_yaml(value), do: value

  defp to_string_key(value) when is_binary(value), do: value
  defp to_string_key(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_key(value), do: to_string(value)

  defp index_operations(%{"paths" => paths}) do
    paths
    |> Enum.flat_map(fn {_path, methods} ->
      Enum.filter(methods, fn {_method, operation} ->
        is_map(operation) and is_binary(operation["operationId"])
      end)
    end)
    |> Map.new(fn {_method, operation} -> {operation["operationId"], operation} end)
  end
end
