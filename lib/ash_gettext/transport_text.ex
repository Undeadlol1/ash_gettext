defmodule AshGettext.TransportText do
  @moduledoc """
  Translate a text a transport wrote itself.

  Most errors are translated in the error, below every transport
  (`AshGettext.ErrorTranslation`), so a transport that sends the error's own
  message needs nothing from here. But a transport also writes some text
  itself: JSON:API and GraphQL each put "is required" on a missing value, and
  neither takes it from the error. Such a text exists only once the transport
  has written it, so it is translated there.

  The rules live here, once, and belong to no transport. `AshGettext.JsonApi`
  is the adapter for AshJsonApi. An adapter for another transport is one call:

      AshGettext.TransportText.translate(error.message, domain,
        code: error.code,
        bindings: error.vars,
        actor: context[:actor]
      )

  ## Options

    * `:code` — the transport's code for the error. When the text has no
      catalog entry, the written sentence for the code
      (`AshGettext.AshMessages`) is tried. Needed where a transport bakes a
      value into the text, so the text can never be a msgid.
    * `:bindings` — values for `%{name}` in the text: the error's `vars`, or
      what the transport made of them (`meta` in JSON:API). When they hold a
      `:translation`, the error was already translated below the transport,
      in its actor's language, and that sentence is the answer.
    * `:actor` — who reads the reply. The domain's `locale_resolver` is asked
      for their language. Without an actor, or without an answer, Gettext's
      current language is used.

  A text with no entry, a reply in the source language, a domain with no
  `gettext` block and one with `translate_errors? false` all give the text
  back exactly as it was. Nothing here raises for a text it does not know.
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
        bindings = bindings(Keyword.get(opts, :bindings))

        case Keyword.get(bindings, :translation) do
          carried when is_binary(carried) -> carried
          _none -> looked_up(text, domain, settings, bindings, opts)
        end

      :error ->
        text
    end
  end

  def translate(text, _domain, _opts), do: text

  defp looked_up(text, domain, settings, bindings, opts) do
    locale = locale(domain, settings, Keyword.get(opts, :actor))

    [text, AshMessages.reply_msgid(Keyword.get(opts, :code))]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(text, &translation(&1, settings, bindings, locale))
  end

  defp locale(domain, settings, actor) do
    case Info.language(domain, actor) do
      {_backend, locale} -> locale
      nil -> Gettext.get_locale(settings.backend)
    end
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

  defp bindings(nil), do: []

  defp bindings(values),
    do: Enum.filter(values, &match?({key, _value} when is_atom(key), &1))
end
