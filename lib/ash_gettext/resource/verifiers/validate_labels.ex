defmodule AshGettext.Resource.Verifiers.ValidateLabels do
  @moduledoc """
  Fails compilation when a `label` in the resource's `gettext` block names an
  attribute the resource does not have.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    known = dsl |> Verifier.get_entities([:attributes]) |> MapSet.new(& &1.name)

    dsl
    |> Verifier.get_entities([:gettext])
    |> Enum.reject(&MapSet.member?(known, &1.attribute))
    |> case do
      [] ->
        :ok

      [label | _] ->
        {:error,
         Spark.Error.DslError.exception(
           module: Verifier.get_persisted(dsl, :module),
           path: [:gettext, :label, label.attribute],
           message:
             "label #{inspect(label.attribute)} names an attribute this resource does not have"
         )}
    end
  end
end
