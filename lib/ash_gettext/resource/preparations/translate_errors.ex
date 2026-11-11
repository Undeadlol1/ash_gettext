defmodule AshGettext.Resource.Preparations.TranslateErrors do
  @moduledoc """
  Translates the errors of a read action. Added to every resource that uses
  `AshGettext.Resource`; you never call it.

  Read actions have no `error_handler`. This translates the errors the query
  has when it is prepared, and the errors of the read itself.
  """

  use Ash.Resource.Preparation

  alias AshGettext.ErrorTranslation.ErrorHandler

  @impl true
  def prepare(query, _opts, _context) do
    query
    |> translated()
    |> Ash.Query.after_transaction(fn
      query, {:error, %Ash.Query{} = failed} ->
        {:error, translated(%{failed | domain: query.domain})}

      query, {:error, error} ->
        {:error, ErrorHandler.translate_error(query, error)}

      _query, read ->
        read
    end)
  end

  defp translated(query),
    do: %{query | errors: ErrorHandler.translate_error(query, query.errors)}
end
