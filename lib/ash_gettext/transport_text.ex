defmodule AshGettext.TransportText do
  @moduledoc """
  Translates a text a transport wrote itself. Used by `AshGettext.JsonApi` and
  `AshGettext.Graphql`; you never call it.

  Notes for maintainers: maintainers/why-some-errors-are-hard.md in the repository.
  """

  alias AshGettext.AshMessages
  alias AshGettext.Info

  @type option :: {:code, term()} | {:bindings, Enumerable.t()} | {:actor, term()}

  @doc """
  The text in the reader's language, or the text itself when there is no translation.
  """
  @spec translate(term(), module() | nil, [option()]) :: term()
  def translate(text, domain, opts \\ [])

  def translate(text, domain, opts) when is_binary(text) and not is_nil(domain) do
    case Info.settings(domain) do
      {:ok, settings} ->
        looked_up(text, domain, settings, bindings(Keyword.get(opts, :bindings)), opts)

      :error ->
        text
    end
  end

  def translate(text, _domain, _opts), do: text

  defp looked_up(text, domain, settings, bindings, opts) do
    locale = Info.locale(domain, Keyword.get(opts, :actor), settings.backend)

    [text, AshMessages.reply_msgid(Keyword.get(opts, :code))]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(text, &translation(&1, settings, bindings, locale))
  end

  defp translation(msgid, settings, bindings, locale) do
    case AshGettext.translate_or_missing(
           settings.backend,
           settings.text_domain,
           msgid,
           bindings,
           locale
         ) do
      {:ok, translated} -> translated
      {:missing, _untranslated} -> nil
    end
  end

  defp bindings(values) when is_list(values) or is_map(values),
    do: Enum.filter(values, &match?({key, _value} when is_atom(key), &1))

  defp bindings(_none), do: []
end
