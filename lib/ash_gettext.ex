defmodule AshGettext do
  @moduledoc """
  Translate the text an Ash app shows: strings, plurals, enum values and attribute names.

      AshGettext.translate(MyApp.Gettext, "default", "Order shipped", [], "ru")
      #=> "Заказ отправлен"

  Every input is an argument, including the language, and nothing is read
  from global state. So a translation works the same from any process, and a
  test of one is a single assertion with no setup.

  The text you write is the msgid. In the source language (the backend's
  configured `:default_locale`, else the global `:gettext` one, else `"en"`)
  it is also the translation, so that language needs no catalog.

  ## Missing translations are observable

  `translate_or_missing/5` reports `{:missing, fallback}` rather than silently
  handing back the msgid, so a test can assert that a string really *is*
  covered in a locale:

      assert {:ok, _} = AshGettext.translate_or_missing(MyApp.Gettext, "default", "Order shipped", [], "ru")

  The detection is gettext's own signal: a lookup that misses returns the msgid
  unchanged. In the source locale `translate_or_missing/5` always reports
  `:ok`. In a translated locale, an *identity* translation (a catalog mapping a
  msgid to itself) is indistinguishable from a miss and is reported as
  `:missing`. Use `translate/5` when you only want the string.

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

    Gettext.with_locale(backend, locale, fn ->
      :dgettext
      |> lookup_in_backend([backend, text_domain, msgid, to_bindings(bindings)])
      |> mark_covered_or_missing(backend, locale, [msgid])
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
    bindings = bindings |> to_bindings() |> Keyword.put_new(:count, count)

    Gettext.with_locale(backend, locale, fn ->
      :dngettext
      |> lookup_in_backend([backend, text_domain, msgid, msgid_plural, count, bindings])
      |> mark_covered_or_missing(backend, locale, [msgid, msgid_plural])
    end)
  end

  @doc """
  The translated label of one value of an `Ash.Type.Enum`.

  The msgid is `enum_module.label(value)`: the value's custom `label:` or, by
  default, the humanized value (`:awaiting_pickup` is `"Awaiting pickup"`). A
  value missing from the catalog falls back to that label, and the miss is
  reported through telemetry like `translate/5`. Use `enum_label_or_missing/5`
  to assert coverage.

  Raises `ArgumentError` when `enum_module` is not an `Ash.Type.Enum`.
  """
  @spec enum_label(backend(), text_domain(), module(), msgid(), locale()) :: String.t()
  def enum_label(backend, text_domain, enum_module, value, locale) do
    backend
    |> enum_label_or_missing(text_domain, enum_module, value, locale)
    |> report_missing(backend, text_domain, label_msgid!(enum_module, value), locale)
    |> text_of()
  end

  @doc """
  The label for an enum value, reporting whether the catalog covered it.
  """
  @spec enum_label_or_missing(backend(), text_domain(), module(), msgid(), locale()) ::
          {:ok, String.t()} | {:missing, String.t()}
  def enum_label_or_missing(backend, text_domain, enum_module, value, locale) do
    translate_or_missing(backend, text_domain, label_msgid!(enum_module, value), [], locale)
  end

  @doc """
  The translated name of a resource attribute.

  The msgid is `attribute_msgid/1`: the attribute name in sentence case
  (`:date_of_birth` is `"Date of birth"`). Misses fall back to it and are
  reported through telemetry. Raises `ArgumentError` for an unknown attribute.
  """
  @spec attribute_label(backend(), text_domain(), module(), atom(), locale()) :: String.t()
  def attribute_label(backend, text_domain, resource, attribute, locale) do
    backend
    |> attribute_label_or_missing(text_domain, resource, attribute, locale)
    |> report_missing(backend, text_domain, attribute_msgid!(resource, attribute), locale)
    |> text_of()
  end

  @doc """
  The name of a resource attribute, reporting whether the catalog covered it.
  """
  @spec attribute_label_or_missing(backend(), text_domain(), module(), atom(), locale()) ::
          {:ok, String.t()} | {:missing, String.t()}
  def attribute_label_or_missing(backend, text_domain, resource, attribute, locale) do
    translate_or_missing(
      backend,
      text_domain,
      attribute_msgid!(resource, attribute),
      [],
      locale
    )
  end

  @doc """
  The msgid an attribute name is looked up under: sentence case,
  `:date_of_birth` -> `"Date of birth"`.
  """
  @spec attribute_msgid(atom() | String.t()) :: String.t()
  def attribute_msgid(attribute) do
    attribute
    |> to_msgid()
    |> String.replace("_", " ")
    |> String.capitalize()
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

  defp mark_covered_or_missing(translated, backend, locale, msgids) do
    if translated in msgids and not source_locale?(backend, locale),
      do: {:missing, translated},
      else: {:ok, translated}
  end

  # In gettext the source text IS the msgid, so an echoed msgid in the source
  # locale is a hit.
  defp source_locale?(backend, locale), do: locale == source_locale(backend)

  # Gettext's runtime entry points are reached through apply/3 so the compiler
  # treats the msgid as data. Calling them directly makes gettext's extraction
  # macros try to record a msgid that is only known at runtime.
  defp lookup_in_backend(entry_point, args) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(Gettext, entry_point, args)
  end

  defp label_msgid!(enum_module, value) do
    unless Code.ensure_loaded?(enum_module) and function_exported?(enum_module, :label, 1) do
      raise ArgumentError, "#{inspect(enum_module)} is not an Ash.Type.Enum"
    end

    enum_module.label(value)
  end

  defp attribute_msgid!(resource, attribute) do
    unless Ash.Resource.Info.attribute(resource, attribute) do
      raise ArgumentError, "#{inspect(resource)} has no attribute #{inspect(attribute)}"
    end

    attribute_msgid(attribute)
  end

  defp to_msgid(msgid) when is_atom(msgid), do: Atom.to_string(msgid)
  defp to_msgid(msgid) when is_binary(msgid), do: msgid

  defp to_bindings(bindings) when is_list(bindings), do: bindings
  defp to_bindings(bindings) when is_map(bindings), do: Enum.to_list(bindings)
end
