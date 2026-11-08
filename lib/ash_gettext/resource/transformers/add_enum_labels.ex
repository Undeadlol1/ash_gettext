defmodule AshGettext.Resource.Transformers.AddEnumLabels do
  @moduledoc """
  Adds a public `<attribute>_label` calculation for every attribute whose
  type is an `AshGettext.Enum` (or a list of one). A resource that already has
  a field with that name keeps it.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    taken =
      for path <- [[:attributes], [:calculations], [:aggregates], [:relationships]],
          entity <- Transformer.get_entities(dsl_state, path),
          into: MapSet.new(),
          do: entity.name

    dsl_state
    |> Transformer.get_entities([:attributes])
    |> Enum.reduce(dsl_state, fn attribute, acc ->
      with {:ok, enum, type} <- enum_type(attribute.type),
           name = :"#{attribute.name}_label",
           false <- MapSet.member?(taken, name) do
        entity =
          Transformer.build_entity!(Ash.Resource.Dsl, [:calculations], :calculate,
            name: name,
            type: type,
            public?: true,
            calculation:
              {AshGettext.Calculations.EnumLabel, attribute: attribute.name, enum: enum}
          )

        Transformer.add_entity(acc, [:calculations], entity)
      else
        _skip -> acc
      end
    end)
    |> then(&{:ok, &1})
  end

  defp enum_type({:array, type}) do
    with {:ok, enum, _} <- enum_type(type), do: {:ok, enum, {:array, :string}}
  end

  defp enum_type(type) when is_atom(type) do
    if Code.ensure_compiled(type) == {:module, type} and
         function_exported?(type, :__ash_gettext_enum__, 0),
       do: {:ok, type, :string},
       else: :error
  end

  defp enum_type(_type), do: :error
end
