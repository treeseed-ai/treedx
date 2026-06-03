defmodule TreeDb.Observability.Scrubber do
  @moduledoc false

  @redacted "redacted"

  @secret_key ~r/(authorization|token|accesstoken|refreshtoken|secret|password|credential|privatekey|jwt|bearer)/i
  @bearer ~r/Bearer\s+[A-Za-z0-9._~+\/=-]+/
  @jwt ~r/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/
  @credential_url ~r/^(https?|ssh):\/\/[^\/@\s]+:[^\/@\s]+@/i
  @treedb_secret ~r/TREEDB_[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|KEY|CREDENTIAL)[A-Z0-9_]*/
  @tmp_path ~r/\/tmp\/[^\s"]*/i
  @var_path ~r/\/var\/lib\/treedb[^\s"]*/i

  @allowed_label_keys MapSet.new([
                        "method",
                        "route",
                        "status_class",
                        "error_code",
                        "operation",
                        "backend",
                        "mode",
                        "status",
                        "capability",
                        "check"
                      ])

  def scrub(value), do: scrub_value(value, nil)

  def scrub_labels(labels) when is_map(labels) do
    labels
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key = to_string(key)

      if MapSet.member?(@allowed_label_keys, key) do
        Map.put(acc, camel_to_snake(key), value |> scrub() |> to_string())
      else
        acc
      end
    end)
  end

  def scrub_labels(_labels), do: %{}

  def scrub_url(url) when is_binary(url) do
    Regex.replace(~r/^([^:]+:\/\/)([^\/@\s]+@)(.*)$/i, url, "\\1redacted@\\3")
  end

  def scrub_url(value), do: value

  def secret_like?(value) when is_binary(value) do
    value =~ @bearer or value =~ @jwt or value =~ @credential_url or value =~ @treedb_secret or
      value =~ @tmp_path or value =~ @var_path or data_dir_path?(value)
  end

  def secret_like?(_value), do: false

  defp scrub_value(value, key) when is_map(value) do
    value
    |> Enum.map(fn {child_key, child_value} ->
      string_key = to_string(child_key)
      {child_key, scrub_value(child_value, string_key)}
    end)
    |> Enum.into(%{})
    |> redact_keyed_value(key)
  end

  defp scrub_value(value, key) when is_list(value) do
    value
    |> Enum.map(&scrub_value(&1, key))
    |> redact_keyed_value(key)
  end

  defp scrub_value(value, key) when is_binary(value) do
    cond do
      key && key =~ @secret_key -> @redacted
      secret_like?(value) -> @redacted
      true -> scrub_url(value)
    end
  end

  defp scrub_value(value, key), do: redact_keyed_value(value, key)

  defp redact_keyed_value(value, key) when is_binary(key) do
    if key =~ @secret_key, do: @redacted, else: value
  end

  defp redact_keyed_value(value, _key), do: value

  defp data_dir_path?(value) do
    data_dir = TreeDb.Store.data_dir() |> Path.expand()
    String.starts_with?(Path.expand(value), data_dir)
  rescue
    _ -> false
  end

  defp camel_to_snake(key) do
    key
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end
end
