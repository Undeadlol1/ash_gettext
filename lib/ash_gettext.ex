defmodule AshGettext do
  @moduledoc """
  Translate the text an Ash app shows: strings, plurals, enum labels and attribute labels.

  Enum values translate themselves: see `AshGettext.Enum`.

      AshGettext.translate(MyApp.Gettext, "default", "Order shipped", [], "ru")
      #=> "Заказ отправлен"

  Every input is an argument, including the language, and nothing is read
  from global state. So a translation works the same from any process, and a
  test of one is a single assertion.

  The text you write is the msgid. In the source language (the backend's
  configured `:default_locale`, else the global `:gettext` one, else `"en"`)
  it is also the translation, so that language needs no catalog.

  ## Missing translations are observable

  `translate_or_missing/5` reports `{:missing, fallback}` rather than silently
  handing back the msgid, so a test can assert that a string really *is*
  covered in a locale:

      assert {:ok, _} = AshGettext.translate_or_missing(MyApp.Gettext, "default", "Order shipped", [], "ru")

  The detection is gettext's own signal: the backend answers a hit as found
  and a miss through its `handle_missing_translation` callback, which a hit
  never calls. In the source locale `translate_or_missing/5` always reports
  `:ok`. When a binding the text needs is left out, gettext answers both
  alike, so a text equal to the untranslated msgid counts as `:missing`. Use
  `translate/5` when you only want the string.

  To translate Ash's error messages as well, see `AshGettext.Domain`.
  """

  @type backend :: module()
  @type text_domain :: String.t()
  @type msgid :: String.t() | atom()
  @type bindings :: Keyword.t() | map()
  @type locale :: String.t()

  @doc """
  Translate `msgid` and return the string, falling back to the msgid on a miss.
  """
  @spec translate(backend(), text_domain(), msgid(), bindings(), locale()) :: String.t()
  def translate(backend, text_domain, msgid, bindings, locale) do
    backend
    |> translate_or_missing(text_domain, msgid, bindings, locale)
    |> report_missing(backend, text_domain, to_msgid(msgid), locale)
    |> text_of()
  end

  @doc """
  Translate `msgid`, reporting whether the catalog actually covered it.
  """
  @spec translate_or_missing(backend(), text_domain(), msgid(), bindings(), locale()) ::
          {:ok, String.t()} | {:missing, String.t()}
  def translate_or_missing(backend, text_domain, msgid, bindings, locale) do
    msgid = to_msgid(msgid)
    bindings = bindings |> to_bindings() |> Map.new()

    locale
    |> backend.lgettext(text_domain, nil, msgid, bindings)
    |> covered_or_missing(backend, {locale, text_domain, msgid}, msgid, bindings)
  end

  @doc false
  # An error text may have a value written into it that the error still lists
  # ("must match ~r/a/" with `match: ~r/a/`). Putting `%{match}` back gives
  # the msgid.
  # ponytail: plain text replace; it only counts when the result is in the catalog.
  # Each text domain is tried in turn; when all miss, the first miss is returned.
  @spec translate_error_text(backend(), [text_domain()], String.t(), bindings(), locale()) ::
          {:ok, String.t()} | {:missing, String.t()}
  def translate_error_text(backend, text_domains, text, bindings, locale) do
    Enum.reduce_while(text_domains, nil, fn text_domain, first_miss ->
      case translate_error_text_in(backend, text_domain, text, bindings, locale) do
        {:ok, _translated} = found -> {:halt, found}
        missing -> {:cont, first_miss || missing}
      end
    end)
  end

  @doc false
  @spec translate_error_sentence(backend(), [text_domain()], String.t(), bindings(), locale()) ::
          String.t()
  def translate_error_sentence(backend, [text_domain | _] = text_domains, msgid, bindings, locale) do
    backend
    |> translate_error_text(text_domains, msgid, bindings, locale)
    |> report_missing(backend, text_domain, msgid, locale)
    |> text_of()
  end

  defp translate_error_text_in(backend, text_domain, text, bindings, locale) do
    with {:missing, _untranslated} = missing <-
           translate_or_missing(backend, text_domain, text, bindings, locale) do
      case with_names_for_values(text, bindings) do
        {msgid, written} when msgid != text ->
          translate_or_missing(
            backend,
            text_domain,
            msgid,
            Keyword.merge(bindings, written),
            locale
          )

        _nothing_written ->
          missing
      end
    end
  end

  defp with_names_for_values(text, bindings) do
    Enum.reduce(bindings, {text, []}, fn {name, value}, {text, written} ->
      shown = if is_binary(value), do: value, else: inspect(value)

      if shown != "" and String.contains?(text, shown),
        do: {String.replace(text, shown, "%{#{name}}"), [{name, shown} | written]},
        else: {text, written}
    end)
  end

  @doc """
  Translate a pluralised `msgid`, returning the string.

  `count` is always available to the catalog as the `%{count}` binding, and it
  wins over a `:count` the caller happens to pass in bindings — the number that
  selected the plural form is the number the sentence shows.
  """
  @spec translate_plural(
          backend(),
          text_domain(),
          msgid(),
          msgid(),
          non_neg_integer(),
          bindings(),
          locale()
        ) :: String.t()
  def translate_plural(backend, text_domain, msgid, msgid_plural, count, bindings, locale) do
    backend
    |> translate_plural_or_missing(text_domain, msgid, msgid_plural, count, bindings, locale)
    |> report_missing(backend, text_domain, to_msgid(msgid), locale)
    |> text_of()
  end

  @doc """
  Translate a pluralised `msgid`, reporting whether the catalog covered it.
  """
  @spec translate_plural_or_missing(
          backend(),
          text_domain(),
          msgid(),
          msgid(),
          non_neg_integer(),
          bindings(),
          locale()
        ) :: {:ok, String.t()} | {:missing, String.t()}
  def translate_plural_or_missing(
        backend,
        text_domain,
        msgid,
        msgid_plural,
        count,
        bindings,
        locale
      ) do
    msgid = to_msgid(msgid)
    msgid_plural = to_msgid(msgid_plural)
    bindings = bindings |> to_bindings() |> Map.new() |> Map.put_new(:count, count)
    form = if count == 1, do: msgid, else: msgid_plural

    locale
    |> backend.lngettext(text_domain, nil, msgid, msgid_plural, count, bindings)
    |> covered_or_missing(backend, {locale, text_domain, msgid}, form, bindings)
  end

  @doc """
  The translated label of a resource attribute, in Gettext's current language.

  The text is the one you wrote in the resource's `gettext` block
  (`label :delivery_date, "Delivery date"`). It is never made from the
  attribute's code name. The backend and text domain come from the resource's
  domain (`AshGettext.Domain`). Misses fall back to the written text and are
  reported through telemetry. Raises `ArgumentError` for an unknown attribute,
  an attribute with no written label, or a resource whose domain has no
  `gettext` block.
  """
  @spec attribute_label(module(), atom()) :: String.t()
  def attribute_label(resource, attribute) do
    {backend, text_domain, msgid} = attribute_lookup!(resource, attribute)

    backend
    |> translate_or_missing(text_domain, msgid, [], Gettext.get_locale(backend))
    |> report_missing(backend, text_domain, msgid, Gettext.get_locale(backend))
    |> text_of()
  end

  @doc """
  The label of a resource attribute, reporting whether the catalog covered it.
  """
  @spec attribute_label_or_missing(module(), atom()) ::
          {:ok, String.t()} | {:missing, String.t()}
  def attribute_label_or_missing(resource, attribute) do
    {backend, text_domain, msgid} = attribute_lookup!(resource, attribute)
    translate_or_missing(backend, text_domain, msgid, [], Gettext.get_locale(backend))
  end

  @doc """
  The locales `backend` ships catalogs for.

  Derived from the backend rather than re-declared in config, so the supported
  list can never drift from the catalogs on disk.
  """
  @spec known_locales(backend()) :: [locale()]
  def known_locales(backend) do
    Enum.uniq([source_locale(backend) | Gettext.known_locales(backend)])
  end

  @doc """
  The backend's source locale: the language its msgids are written in, which
  needs no catalog.
  """
  @spec source_locale(backend()) :: locale()
  def source_locale(backend) do
    if function_exported?(backend, :__gettext__, 1),
      do: backend.__gettext__(:default_locale),
      else: Application.get_env(:gettext, :default_locale, "en")
  end

  # Emits `[:ash_gettext, :translation, :missing]` so an app can count gaps.
  defp report_missing({:missing, _} = result, backend, text_domain, msgid, locale) do
    :telemetry.execute([:ash_gettext, :translation, :missing], %{count: 1}, %{
      backend: backend,
      text_domain: text_domain,
      msgid: msgid,
      locale: locale
    })

    result
  end

  defp report_missing(result, _backend, _text_domain, _msgid, _locale), do: result

  defp text_of({:ok, translated}), do: translated
  defp text_of({:missing, fallback}), do: fallback

  defp covered_or_missing({:ok, translated}, _backend, _lookup, _form, _bindings),
    do: {:ok, translated}

  defp covered_or_missing({:default, fallback}, backend, {locale, _, _}, _form, _bindings),
    do: missing_unless_source(backend, locale, fallback)

  # Gettext answers a hit and a miss alike when a binding is left out, so the
  # text is compared with what a miss would read.
  defp covered_or_missing(
         {:missing_bindings, incomplete, missing},
         backend,
         {locale, text_domain, msgid},
         form,
         bindings
       ) do
    text =
      backend.handle_missing_bindings(
        %Gettext.MissingBindingsError{
          backend: backend,
          locale: locale,
          domain: text_domain,
          msgctxt: nil,
          msgid: msgid,
          missing: missing
        },
        incomplete
      )

    if incomplete == untranslated(backend, form, bindings),
      do: missing_unless_source(backend, locale, text),
      else: {:ok, text}
  end

  defp untranslated(backend, form, bindings) do
    case backend.__gettext__(:interpolation).runtime_interpolate(form, bindings) do
      {:ok, text} -> text
      {:missing_bindings, incomplete, _missing} -> incomplete
    end
  end

  # In gettext the source text IS the msgid, so an echoed msgid in the source
  # locale is a hit.
  defp missing_unless_source(backend, locale, text) do
    if locale == source_locale(backend), do: {:ok, text}, else: {:missing, text}
  end

  defp attribute_lookup!(resource, attribute) do
    unless Ash.Resource.Info.attribute(resource, attribute) do
      raise ArgumentError, "#{inspect(resource)} has no attribute #{inspect(attribute)}"
    end

    case AshGettext.Info.locale_settings(Ash.Resource.Info.domain(resource)) do
      {:ok, settings} ->
        {settings.backend, settings.text_domain, written_label!(resource, attribute)}

      :error ->
        raise ArgumentError, "the domain of #{inspect(resource)} has no gettext block"
    end
  end

  defp written_label!(resource, attribute) do
    AshGettext.Info.attribute_label(resource, attribute) ||
      raise ArgumentError,
            "#{inspect(resource)} has no written label for #{inspect(attribute)}. " <>
              "Add `label #{inspect(attribute)}, \"...\"` to its `gettext` block."
  end

  defp to_msgid(msgid) when is_atom(msgid), do: Atom.to_string(msgid)
  defp to_msgid(msgid) when is_binary(msgid), do: msgid

  defp to_bindings(bindings) when is_list(bindings), do: bindings
  defp to_bindings(bindings) when is_map(bindings), do: Enum.to_list(bindings)
end
