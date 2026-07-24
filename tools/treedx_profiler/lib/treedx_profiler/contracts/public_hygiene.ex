defmodule TreeDxProfiler.PublicHygiene do
  @moduledoc false

  @forbidden_patterns [
    ~r{/tmp/},
    ~r{/var/lib/treedx},
    ~r{/workspace/treedx},
    ~r{authorization}i,
    ~r{bearer\s+[A-Za-z0-9._-]+}i,
    ~r{eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+},
    ~r{://[^/\s:]+:[^@\s]+@},
    ~r{stdout}i,
    ~r{stderr}i
  ]

  def validate(payload) do
    text = inspect(payload, limit: :infinity, printable_limit: :infinity)

    case Enum.find(@forbidden_patterns, &Regex.match?(&1, text)) do
      nil ->
        :ok

      pattern ->
        {:error, "response contained unsanitized public detail matching #{inspect(pattern)}"}
    end
  end

  def scrub(payload) when is_binary(payload) do
    Enum.reduce(@forbidden_patterns, payload, fn pattern, acc ->
      Regex.replace(pattern, acc, "redacted")
    end)
  end

  def scrub(payload) when is_map(payload) do
    payload
    |> Jason.encode!()
    |> scrub()
    |> Jason.decode!()
  rescue
    _ -> %{"scrubbed" => true}
  end

  def scrub(payload), do: payload
end
