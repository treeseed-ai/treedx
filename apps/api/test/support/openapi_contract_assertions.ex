defmodule TreeDbWeb.OpenApiContractAssertions do
  import ExUnit.Assertions

  @openapi_json Path.expand("../../../../docs/api/openapi.json", __DIR__)

  def openapi do
    @openapi_json
    |> File.read!()
    |> Jason.decode!()
  end

  def operation(openapi, method, path) do
    get_in(openapi, ["paths", path, String.downcase(to_string(method))])
  end

  def assert_success_envelope!(payload) do
    assert is_map(payload)
    assert payload["ok"] == true
  end

  def assert_error_envelope!(payload) do
    assert is_map(payload)
    assert payload["ok"] == false
    assert is_map(payload["error"])
    assert is_binary(payload["error"]["code"])
    assert is_binary(payload["error"]["message"])
  end

  def assert_matches_success_schema!(openapi, method, path, payload) do
    assert_success_envelope!(payload)

    schema =
      openapi
      |> operation(method, path)
      |> get_in(["responses", "200", "content", "application/json", "schema"])
      |> resolve_schema(openapi)

    assert_schema!(payload, schema, openapi)
  end

  def assert_matches_error_schema!(openapi, method, path, payload) do
    assert_error_envelope!(payload)

    schema =
      openapi
      |> operation(method, path)
      |> get_in(["responses", "401"])
      |> resolve_response(openapi)
      |> get_in(["content", "application/json", "schema"])
      |> resolve_schema(openapi)

    assert_schema!(payload, schema, openapi)
  end

  def assert_schema!(value, %{"oneOf" => schemas}, openapi) do
    assert Enum.any?(schemas, fn schema -> schema_match?(value, schema, openapi) end),
           "expected #{inspect(value)} to match oneOf schema"
  end

  def assert_schema!(value, %{"anyOf" => schemas}, openapi) do
    assert Enum.any?(schemas, fn schema -> schema_match?(value, schema, openapi) end),
           "expected #{inspect(value)} to match anyOf schema"
  end

  def assert_schema!(value, %{"const" => expected}, _openapi), do: assert(value == expected)
  def assert_schema!(value, %{"type" => "string"}, _openapi), do: assert(is_binary(value))
  def assert_schema!(value, %{"type" => "integer"}, _openapi), do: assert(is_integer(value))
  def assert_schema!(value, %{"type" => "number"}, _openapi), do: assert(is_number(value))
  def assert_schema!(value, %{"type" => "boolean"}, _openapi), do: assert(is_boolean(value))
  def assert_schema!(nil, %{"type" => "null"}, _openapi), do: assert(is_nil(nil))

  def assert_schema!(value, %{"type" => "array", "items" => item_schema}, openapi) do
    assert is_list(value)
    Enum.each(value, &assert_schema!(&1, resolve_schema(item_schema, openapi), openapi))
  end

  def assert_schema!(value, %{"type" => "object"} = schema, openapi) do
    assert is_map(value)

    for required <- Map.get(schema, "required", []) do
      assert Map.has_key?(value, required), "missing required key #{required}"
    end

    properties = Map.get(schema, "properties", %{})

    for {key, property_schema} <- properties, Map.has_key?(value, key) do
      assert_schema!(value[key], resolve_schema(property_schema, openapi), openapi)
    end

    if Map.get(schema, "additionalProperties") == false do
      allowed = MapSet.new(Map.keys(properties))
      extras = value |> Map.keys() |> Enum.reject(&MapSet.member?(allowed, &1))
      assert extras == [], "unexpected keys #{inspect(extras)}"
    end
  end

  def assert_schema!(_value, _schema, _openapi), do: :ok

  defp schema_match?(value, schema, openapi) do
    assert_schema!(value, resolve_schema(schema, openapi), openapi)
    true
  rescue
    ExUnit.AssertionError -> false
  end

  defp resolve_response(%{"$ref" => ref}, openapi), do: resolve_ref(openapi, ref)
  defp resolve_response(response, _openapi), do: response

  defp resolve_schema(%{"$ref" => ref}, openapi), do: resolve_ref(openapi, ref)
  defp resolve_schema(schema, _openapi), do: schema

  defp resolve_ref(openapi, "#/" <> pointer) do
    Enum.reduce(String.split(pointer, "/"), openapi, fn part, acc ->
      Map.fetch!(acc, part)
    end)
  end
end
