defmodule TreeDx.Files.PatchTest do
  use ExUnit.Case, async: true
  alias TreeDx.Files.Patch, as: FilePatch
  alias TreeDx.Files.ChangesetPatch

  @contents [
    nil,
    "",
    "one",
    "one\n",
    "one\n\n",
    "\n",
    "one\ntwo",
    "one\ntwo\n",
    "α\nβ\n",
    "one\r\ntwo\r\n"
  ]

  for {before, i} <- Enum.with_index(@contents),
      {after_content, j} <- Enum.with_index(@contents),
      before != after_content do
    test "matches Git byte-for-byte for source #{i} and destination #{j}" do
      before = unquote(before)
      after_content = unquote(after_content)

      directory =
        Path.join(
          System.tmp_dir!(),
          "treedx-patch-#{System.unique_integer([:positive, :monotonic])}"
        )

      File.mkdir!(directory)
      on_exit(fn -> File.rm_rf!(directory) end)
      old_path = write_side(directory, "old", before)
      new_path = write_side(directory, "new", after_content)

      {patch, 1} =
        System.cmd(
          "git",
          ["diff", "--no-index", "--no-ext-diff", "--no-color", "--", old_path, new_path],
          stderr_to_stdout: true
        )

      patch = normalize_patch(patch, before, after_content)

      assert FilePatch.apply(before || "", patch, "docs/file.md") == {:ok, after_content || ""}
    end
  end

  defp normalize_patch(patch, before, after_content) do
    patch
    |> String.replace(~r/^diff --git .*$/m, "diff --git a/docs/file.md b/docs/file.md")
    |> String.replace(
      ~r/^--- .*$/m,
      if(is_nil(before), do: "--- /dev/null", else: "--- a/docs/file.md")
    )
    |> String.replace(
      ~r/^\+\+\+ .*$/m,
      if(is_nil(after_content), do: "+++ /dev/null", else: "+++ b/docs/file.md")
    )
  end

  test "accepts omitted counts and rejects malformed or misplaced hunks" do
    assert FilePatch.apply("old\n", "@@ -1 +1 @@\n-old\n+new\n", "file") == {:ok, "new\n"}

    for patch <- [
          "@@ -1,2 +1,1 @@\n-old\n+new\n",
          "@@ -1,1 +1,1 @@\n-old\n+new\n\n",
          "@@ -1 +1 @@\n-wrong\n+new\n",
          "@@ -1 +2 @@\n-old\n+new\n",
          "@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file\n\\ No newline at end of file\n",
          "@@ -1 +1 @@\n\\ No newline at end of file\n-old\n+new\n",
          "@@ -1 +1 @@\n-old\n+new\n@@ -1 +1 @@\n-old\n+again\n"
        ] do
      assert {:error, _} = FilePatch.apply("old\n", patch, "file")
    end
  end

  test "changeset sections retain bytes and support explicit empty files" do
    patch =
      "diff --git a/docs/a b/docs/a\nnew file mode 100644\n--- /dev/null\n+++ b/docs/a\n@@ -0,0 +1 @@\n+hello\n\\ No newline at end of file\ndiff --git a/docs/b b/docs/b\nnew file mode 100644\n--- /dev/null\n+++ b/docs/b\n"

    assert {:ok, [first, second]} = ChangesetPatch.parse(patch)
    assert FilePatch.apply("", first.patch, first.path) == {:ok, "hello"}
    assert FilePatch.apply("", second.patch, second.path) == {:ok, ""}
    assert {:error, _} = ChangesetPatch.parse(patch <> "+undeclared\n")
  end

  test "file-like body text is not mistaken for a target header" do
    patch = "--- a/file\n+++ b/file\n@@ -1 +1 @@\n--- old\n+++ new\n"
    assert FilePatch.apply("-- old\n", patch, "file") == {:ok, "++ new\n"}
  end

  test "applies separated hunks without dropping unchanged bytes" do
    assert FilePatch.apply(
             "a\nb\nc\nd\ne\n",
             "@@ -1 +1 @@\n-a\n+A\n@@ -5 +5 @@\n-e\n+E\n",
             "file"
           ) == {:ok, "A\nb\nc\nd\nE\n"}
  end

  test "does not allow a missing newline inside the resulting file" do
    assert {:error, _} =
             FilePatch.apply(
               "a\nb\n",
               "@@ -1 +1 @@\n-a\n+A\n\\ No newline at end of file\n",
               "file"
             )

    assert {:error, _} = FilePatch.apply("data", "deleted file mode 100644\n", "file")
  end

  defp write_side(_directory, _name, nil), do: "/dev/null"

  defp write_side(directory, name, content) do
    path = Path.join(directory, name)
    File.write!(path, content)
    path
  end
end
