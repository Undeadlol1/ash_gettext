defmodule AshGettext.Resource.Transformers.AttachSetLanguage do
  @moduledoc """
  Sets the language first in every action: a change on each create, update
  and destroy action, and one global preparation for reads.

  It goes on each action rather than into the resource's global changes
  because Ash runs an action's own validations before global changes, and
  those validations already add errors that the error handler translates.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:actions])
    |> Enum.reduce(dsl_state, &install/2)
    |> add_read_preparation()
    |> then(&{:ok, &1})
  end

  # A global preparation: one on the primary read action itself makes Ash warn.
  defp add_read_preparation(dsl_state) do
    prep = {AshGettext.SetLanguage.Prepare, []}

    if Enum.any?(Transformer.get_entities(dsl_state, [:preparations]), &(&1.preparation == prep)) do
      dsl_state
    else
      entity =
        Transformer.build_entity!(Ash.Resource.Dsl, [:preparations], :prepare, preparation: prep)

      Transformer.add_entity(dsl_state, [:preparations], entity, type: :prepend)
    end
  end

  defp install(%{type: type} = action, dsl_state) when type in [:create, :update, :destroy] do
    entity =
      Transformer.build_entity!(Ash.Resource.Dsl, [:actions, type], :change,
        change: {AshGettext.SetLanguage, []}
      )

    prepend(dsl_state, action, :changes, entity)
  end

  defp install(_action, dsl_state), do: dsl_state

  defp prepend(dsl_state, action, field, entity) do
    if Enum.any?(
         Map.fetch!(action, field),
         &(&1.__struct__ == entity.__struct__ and module(&1) == module(entity))
       ) do
      dsl_state
    else
      Transformer.replace_entity(
        dsl_state,
        [:actions],
        Map.update!(action, field, &[entity | &1]),
        &(&1.name == action.name and &1.type == action.type)
      )
    end
  end

  defp module(%{change: {module, _}}), do: module
  defp module(%{preparation: {module, _}}), do: module
  defp module(_other), do: nil
end
