defmodule AshGettext do
  @moduledoc """
  Translate the text an Ash app shows: strings, plurals and enum values.

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
  The label a catalog gives one value of an enum attribute.

  The msgid is `"<attribute>.<value>"` — see `enum_msgid/2`. An uncovered value
  falls back to a humanized form of the value itself (`:awaiting_pickup` reads
  as `"Awaiting pickup"`), because the alternative is putting `status.awaiting_pickup`
  in front of a user. The fallback is a stopgap that keeps a screen readable, not
  a substitute for the catalog entry — use `enum_label_or_missing/5` to assert coverage.

  Nothing here touches the attribute or its `Ash.Type.Enum`: this is a function
  a caller uses where they already render, not a change to a resource.
  """
  @spec enum_label(backend(), text_domain(), msgid(), msgid(), locale()) :: String.t()
  def enum_label(backend, text_domain, attribute, value, locale) do
    backend
    |> enum_label_or_missing(text_domain, attribute, value, locale)
    |> text_of()
  end

  @doc """
  The label for an enum value, reporting whether the catalog covered it.
  """
  @spec enum_label_or_missing(backend(), text_domain(), msgid(), msgid(), locale()) ::
          {:ok, String.t()} | {:missing, String.t()}
  def enum_label_or_missing(backend, text_domain, attribute, value, locale) do
    msgid = enum_msgid(attribute, value)

    case translate_or_missing(backend, text_domain, msgid, [], locale) do
      # The source locale echoes an uncovered msgid as a hit; a label must still read as a word.
      {:ok, ^msgid} -> {:ok, humanize(value)}
      {:ok, label} -> {:ok, label}
      {:missing, _msgid} -> {:missing, humanize(value)}
    end
  end

  @doc """
  The msgid an enum value is looked up under: `"<attribute>.<value>"`.

  Public because a catalog author has to know it, and because it is what
  `mix ash_gettext.extract` and any hand-written entry must agree on.
  """
  @spec enum_msgid(msgid(), msgid()) :: String.t()
  def enum_msgid(attribute, value), do: "#{to_msgid(attribute)}.#{to_msgid(value)}"

  @doc """
  The locales `backend` ships catalogs for.

  Derived from the backend rather than re-declared in config, so the supported
  list can never drift from the catalogs on disk.
  """
  @spec known_locales(backend()) :: [locale()]
  def known_locales(backend), do: Gettext.known_locales(backend)

  defp text_of({:ok, translated}), do: translated
  defp text_of({:missing, fallback}), do: fallback

  defp mark_covered_or_missing(translated, backend, locale, msgids) do
    if translated in msgids and not source_locale?(backend, locale),
      do: {:missing, translated},
      else: {:ok, translated}
  end

  # In gettext the source text IS the msgid, so an echoed msgid in the source
  # locale is a hit. The backend's `__gettext__(:default_locale)` already falls
  # back to the global `:gettext` `:default_locale` (gettext's compiler.ex).
  defp source_locale?(backend, locale) do
    default_locale =
      if function_exported?(backend, :__gettext__, 1),
        do: backend.__gettext__(:default_locale),
        else: Application.get_env(:gettext, :default_locale, "en")

    locale == default_locale
  end

  # Gettext's runtime entry points are reached through apply/3 so the compiler
  # treats the msgid as data. Calling them directly makes gettext's extraction
  # macros try to record a msgid that is only known at runtime.
  defp lookup_in_backend(entry_point, args) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(Gettext, entry_point, args)
  end

  # Sentence case, not title case: an enum value is a word, and `Awaiting pickup`
  # is what a person would have written if they had written it.
  defp humanize(value) do
    value
    |> to_msgid()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp to_msgid(msgid) when is_atom(msgid), do: Atom.to_string(msgid)
  defp to_msgid(msgid) when is_binary(msgid), do: msgid

  defp to_bindings(bindings) when is_list(bindings), do: bindings
  defp to_bindings(bindings) when is_map(bindings), do: Enum.to_list(bindings)
end
