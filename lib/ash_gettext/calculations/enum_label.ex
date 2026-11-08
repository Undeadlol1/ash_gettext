defmodule AshGettext.Calculations.EnumLabel do
  @moduledoc """
  The translated label of an enum attribute, in Gettext's current locale.

  `AshGettext.Resource` adds this as `<attribute>_label`. A `nil` value stays
  `nil`; a list attribute gives a list of labels.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, opts, _context), do: [opts[:attribute]]

  @impl true
  def calculate(records, opts, _context) do
    Enum.map(records, fn record ->
      label(opts[:enum], Map.get(record, opts[:attribute]))
    end)
  end

  defp label(enum, values) when is_list(values), do: Enum.map(values, &label(enum, &1))
  defp label(_enum, nil), do: nil
  defp label(enum, value), do: enum.label(value)
end
