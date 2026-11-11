defmodule AshGettext.Resource.Preparations.TranslateErrors do
  @moduledoc """
  Translates the errors of a read action. Added to every resource that uses
  `AshGettext.Resource`; you never call it.

  Read actions have no `error_handler`. This translates the errors the query
  has when it is prepared, and the errors of the read itself. A read with its
  own preparations or validations runs it again as its last preparation
  (`late?: true`), and only that run translates.
  """

  use Ash.Resource.Preparation

  alias AshGettext.ErrorTranslation.ErrorHandler

  @impl true
  def prepare(query, opts, _context) do
    if opts[:late?] || not late_pass?(query.action),
      do: translating(query),
      else: query
  end

  defp late_pass?(%{preparations: preparations}),
    do: Enum.any?(preparations, &match?(%{preparation: {__MODULE__, [late?: true]}}, &1))

  defp late_pass?(_action), do: false

  defp translating(query) do
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
