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
  def calculate(records, opts, context) do
    labels = fn ->
      Enum.map(records, &label(opts[:enum], Map.get(&1, opts[:attribute])))
    end

    # `Ash.load` on records already in hand runs no read action, so nothing set
    # the language yet: take it from the actor here.
    case actor_language(records, context) do
      {backend, locale} -> Gettext.with_locale(backend, locale, labels)
      nil -> labels.()
    end
  end

  defp actor_language([%resource{} | _], %{actor: actor}) when not is_nil(actor) do
    AshGettext.SetLanguage.resolve(Ash.Resource.Info.domain(resource), %{actor: actor})
  end

  defp actor_language(_records, _context), do: nil

  defp label(enum, values) when is_list(values), do: Enum.map(values, &label(enum, &1))
  defp label(_enum, nil), do: nil
  defp label(enum, value), do: enum.label(value)
end
