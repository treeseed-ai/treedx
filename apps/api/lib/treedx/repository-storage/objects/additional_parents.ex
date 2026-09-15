defmodule TreeDx.Files.AdditionalParents do
  @moduledoc false

  def resolve(ctx, params) do
    refs = params["additionalParentRefs"] || []

    cond do
      !is_list(refs) or length(refs) > 1 ->
        {:error,
         %{
           code: "validation_error",
           message: "At most one additional publication parent ref is supported."
         }}

      true ->
        resolve_refs(ctx, refs)
    end
  end

  defp resolve_refs(ctx, refs) do
    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, commits} ->
      with true <- is_binary(ref) and String.starts_with?(ref, "refs/"),
           :ok <- TreeDx.Capabilities.require_ref(ctx.scope, ref),
           {:ok, %{"target" => commit}} <-
             TreeDx.Git.resolve_ref(TreeDx.RepositoryStorage.path!(ctx.repo), ref) do
        {:cont, {:ok, commits ++ [commit]}}
      else
        false ->
          {:halt,
           {:error,
            %{
              code: "validation_error",
              message: "Additional publication parents must be full refs."
            }}}

        error ->
          {:halt, error}
      end
    end)
  end
end
