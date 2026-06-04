defmodule TreeDbProfiler.DataGenerator do
  @moduledoc false

  def markdown(seed, index) do
    """
    # Generated Portfolio Document #{index}

    release provenance migration portfolio generated #{index}

    EntityAlpha#{index} links to System#{rem(index, 17)} and Release#{rem(index, 23)}.

    #{lorem(seed, index)}
    """
  end

  def text(seed, index),
    do: "release provenance migration portfolio text #{index} #{lorem(seed, index)}\n"

  def json(seed, index) do
    Jason.encode!(
      %{
        "id" => index,
        "seed" => seed,
        "term" => "release",
        "kind" => "portfolio",
        "entity" => "EntityAlpha#{index}"
      },
      pretty: true
    ) <> "\n"
  end

  def binary(seed, index, byte_length) do
    stream_seed = "#{seed}:#{index}:#{byte_length}"

    stream_seed
    |> chunks()
    |> Enum.reduce_while(<<>>, fn chunk, acc ->
      next = acc <> chunk

      if byte_size(next) >= byte_length,
        do: {:halt, binary_part(next, 0, byte_length)},
        else: {:cont, next}
    end)
  end

  def sha256(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  def generated_path(kind, counter) do
    case kind do
      :markdown -> "workspace/generated/doc-#{pad(counter)}.md"
      :text -> "workspace/generated/text-#{pad(counter)}.txt"
      :json -> "workspace/generated/item-#{pad(counter)}.json"
      :binary -> "workspace/generated/blob-#{pad(counter)}.bin"
      :delete -> "workspace/generated/delete-#{pad(counter)}.md"
    end
  end

  def repo_name(prefix, profile_id, index), do: "#{prefix}#{profile_id}-repo-#{pad(index)}"

  defp chunks(seed), do: Stream.iterate(0, &(&1 + 1)) |> Stream.map(&hash_chunk(seed, &1))
  defp hash_chunk(seed, index), do: :crypto.hash(:sha256, "#{seed}:#{index}")

  defp lorem(seed, index) do
    words =
      ~w(alpha beta gamma delta epsilon release provenance migration context graph query blob)

    offset = :erlang.phash2({seed, index}, length(words))

    1..24
    |> Enum.map(fn i -> Enum.at(words, rem(offset + i, length(words))) end)
    |> Enum.join(" ")
  end

  defp pad(index), do: index |> Integer.to_string() |> String.pad_leading(6, "0")
end
