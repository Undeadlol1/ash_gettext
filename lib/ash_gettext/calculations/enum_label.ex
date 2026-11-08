defmodule AshGettext.Calculations.EnumLabel do
  @moduledoc """
  The translated label of an enum attribute, in the language of the query's
  actor. With no actor, Gettext's current locale.

  `AshGettext.Resource` adds this as `<attribute>_label`. A `nil` value stays
  `nil`; a list attribute gives a list of labels.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, opts, _context), do: [opts[:attribute]]

  @impl true
  def calculate(records, opts, context) do
    labels = fn ->
      Enum.map(records, &label(opts[:enum], Map.get(&1, opts[:attribute])))
    end

    case language(records, context) do
      {backend, locale} -> Gettext.with_locale(backend, locale, labels)
      nil -> labels.()
    end
  end

  defp language([%resource{} | _], context) do
    AshGettext.Info.language(Ash.Resource.Info.domain(resource), context.actor)
  end

  defp language([], _context), do: nil

  defp label(enum, values) when is_list(values), do: Enum.map(values, &label(enum, &1))
  defp label(_enum, nil), do: nil
  defp label(enum, value), do: enum.label(value)
end
