defmodule TreeDxProfiler.OpenApiResponseValidator do
  @moduledoc false

  def validate_response(operation_id, status, body, opts \\ []) do
    if Keyword.get(opts, :enabled, true) do
      with {:ok, spec} <- load_spec(),
           {:ok, operation} <- find_operation(spec, operation_id),
           {:ok, response_spec} <- find_response(operation, status),
           :ok <- validate_body(spec, response_spec, body) do
        :ok
      else
        {:error, message} -> {:error, message}
      end
    else
      :ok
    end
  end

  def report(assertions) do
    results = Enum.flat_map(assertions, &List.wrap(Map.get(&1, :openapiValidation)))
    failures = Enum.filter(results, &(&1[:passed] == false))

    %{
      "totalResponses" => length(results),
      "passed" => Enum.count(results, &(&1[:passed] != false)),
      "failed" => length(failures),
      "failures" =>
        failures
        |> Enum.take(100)
        |> Enum.map(fn result ->
          %{
            "operationId" => result[:operationId],
            "status" => result[:status],
            "message" => result[:message]
          }
        end)
    }
  end

  defp load_spec do
    env_path = System.get_env("TREEDX_OPENAPI_PATH")

    path =
      [
        env_path,
        Path.expand("docs/api/openapi.json", File.cwd!()),
        Path.expand("../../docs/api/openapi.json", File.cwd!()),
        Path.expand("../../../docs/api/openapi.json", __DIR__)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.find(&File.exists?/1)

    if path do
      {:ok, path |> File.read!() |> Jason.decode!()}
    else
      {:error, "docs/api/openapi.json not found"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp find_operation(%{"paths" => paths}, operation_id) do
    paths
    |> Enum.flat_map(fn {_path, methods} ->
      methods
      |> Enum.filter(fn {_method, operation} ->
        is_map(operation) and operation["operationId"] == operation_id
      end)
      |> Enum.map(fn {_method, operation} -> operation end)
    end)
    |> case do
      [operation | _] -> {:ok, operation}
      [] -> {:error, "operation #{operation_id} not found in OpenAPI"}
    end
  end

  defp find_response(%{"responses" => responses}, status) do
    key = Integer.to_string(status || 0)

    cond do
      Map.has_key?(responses, key) -> {:ok, responses[key]}
      status in 200..299 and Map.has_key?(responses, "2XX") -> {:ok, responses["2XX"]}
      Map.has_key?(responses, "default") -> {:ok, responses["default"]}
      true -> {:error, "status #{key} is not documented"}
    end
  end

  defp validate_body(_spec, response_spec, body) when is_binary(body) do
    content = response_spec["content"] || %{}

    if map_size(content) == 0 or Map.has_key?(content, "text/plain") or
         Map.has_key?(content, "application/octet-stream") do
      :ok
    else
      {:error,
       "response body is text/binary but OpenAPI does not document text or binary content"}
    end
  end

  defp validate_body(spec, response_spec, body) do
    schema =
      response_spec
      |> get_in(["content", "application/json", "schema"])
      |> case do
        nil -> get_in(response_spec, ["content", "application/problem+json", "schema"])
        schema -> schema
      end

    if schema do
      validate_schema(spec, schema, body)
    else
      :ok
    end
  end

  defp validate_schema(spec, %{"$ref" => ref}, value) do
    case resolve_ref(spec, ref) do
      nil -> {:error, "unresolved schema reference #{ref}"}
      schema -> validate_schema(spec, schema, value)
    end
  end

  defp validate_schema(spec, %{"oneOf" => schemas}, value),
    do: validate_any(spec, schemas, value, "oneOf")

  defp validate_schema(spec, %{"anyOf" => schemas}, value),
    do: validate_any(spec, schemas, value, "anyOf")

  defp validate_schema(spec, %{"allOf" => schemas}, value) do
    schemas
    |> Enum.reduce_while(:ok, fn schema, :ok ->
      case validate_schema(spec, schema, value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_schema(spec, %{"type" => "object"} = schema, value) when is_map(value) do
    required = schema["required"] || []

    missing =
      required
      |> Enum.reject(&Map.has_key?(value, &1))

    if missing != [] do
      {:error, "missing required fields #{Enum.join(missing, ", ")}"}
    else
      validate_properties(spec, schema["properties"] || %{}, value)
    end
  end

  defp validate_schema(_spec, %{"type" => "object"}, _value), do: {:error, "expected object"}

  defp validate_schema(spec, %{"type" => "array"} = schema, value) when is_list(value) do
    item_schema = schema["items"] || %{}

    value
    |> Enum.reduce_while(:ok, fn item, :ok ->
      case validate_schema(spec, item_schema, item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_schema(_spec, %{"type" => "array"}, _value), do: {:error, "expected array"}

  defp validate_schema(_spec, %{"type" => "string"} = schema, value) when is_binary(value),
    do: validate_enum(schema, value)

  defp validate_schema(_spec, %{"type" => "string"}, nil), do: :ok
  defp validate_schema(_spec, %{"type" => "string"}, _value), do: {:error, "expected string"}

  defp validate_schema(_spec, %{"type" => type} = schema, value)
       when type in ["number", "integer"] and is_number(value),
       do: validate_enum(schema, value)

  defp validate_schema(_spec, %{"type" => type}, nil) when type in ["number", "integer"], do: :ok

  defp validate_schema(_spec, %{"type" => type}, _value) when type in ["number", "integer"],
    do: {:error, "expected #{type}"}

  defp validate_schema(_spec, %{"type" => "boolean"}, value) when is_boolean(value), do: :ok
  defp validate_schema(_spec, %{"type" => "boolean"}, nil), do: :ok
  defp validate_schema(_spec, %{"type" => "boolean"}, _value), do: {:error, "expected boolean"}
  defp validate_schema(_spec, _schema, _value), do: :ok

  defp validate_any(spec, schemas, value, label) do
    if Enum.any?(schemas, &(validate_schema(spec, &1, value) == :ok)),
      do: :ok,
      else: {:error, "#{label} schemas did not match"}
  end

  defp validate_properties(spec, properties, value) do
    properties
    |> Enum.reduce_while(:ok, fn {key, schema}, :ok ->
      if Map.has_key?(value, key) do
        case validate_schema(spec, schema, value[key]) do
          :ok -> {:cont, :ok}
          {:error, message} -> {:halt, {:error, "#{key}: #{message}"}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_enum(%{"enum" => values}, value) do
    if value in values, do: :ok, else: {:error, "value #{inspect(value)} is not in enum"}
  end

  defp validate_enum(_schema, _value), do: :ok

  defp resolve_ref(spec, "#/components/schemas/" <> name),
    do: get_in(spec, ["components", "schemas", name])

  defp resolve_ref(_spec, _ref), do: nil
end
