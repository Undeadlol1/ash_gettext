defmodule AshGettext do
  @moduledoc """
  Gettext, made ergonomic for Ash — the pure translation core.

  This module is the whole library's foundation and it is deliberately boring:
  every input is an argument, nothing is read from global state, and the result
  depends only on what the caller passed in. That makes a translation test a
  single assertion with no setup, no actor, and no database.

  ## Missing translations are observable

  `fetch/5` reports `{:missing, fallback}` rather than silently handing back the
  msgid, so a test can assert that a string really *is* covered in a locale:

      assert {:ok, _} = AshGettext.fetch(MyApp.Gettext, "errors", "too_low", [], "ru")

  The detection is gettext's own signal — a lookup that misses returns the msgid
  unchanged. One consequence is worth knowing: an *identity* translation, where
  a catalog deliberately maps a msgid to itself (common in an `en` source
  catalog), is indistinguishable from a miss and is reported as `:missing`. Use
  `translate/5` when you only want the string.
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
    |> fetch(text_domain, msgid, bindings, locale)
    |> string()
  end

  @doc """
  Translate `msgid`, reporting whether the catalog actually covered it.
  """
  @spec fetch(backend(), text_domain(), msgid(), bindings(), locale()) ::
          {:ok, String.t()} | {:missing, String.t()}
  def fetch(backend, text_domain, msgid, bindings, locale) do
    msgid = to_msgid(msgid)

    Gettext.with_locale(backend, locale, fn ->
      :dgettext
      |> lookup([backend, text_domain, msgid, to_bindings(bindings)])
      |> classify([msgid])
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
    |> fetch_plural(text_domain, msgid, msgid_plural, count, bindings, locale)
    |> string()
  end

  @doc """
  Translate a pluralised `msgid`, reporting whether the catalog covered it.
  """
  @spec fetch_plural(
          backend(),
          text_domain(),
          msgid(),
          msgid(),
          non_neg_integer(),
          bindings(),
          locale()
        ) :: {:ok, String.t()} | {:missing, String.t()}
  def fetch_plural(backend, text_domain, msgid, msgid_plural, count, bindings, locale) do
    msgid = to_msgid(msgid)
    msgid_plural = to_msgid(msgid_plural)
    bindings = bindings |> to_bindings() |> Keyword.put_new(:count, count)

    Gettext.with_locale(backend, locale, fn ->
      :dngettext
      |> lookup([backend, text_domain, msgid, msgid_plural, count, bindings])
      |> classify([msgid, msgid_plural])
    end)
  end

  @doc """
  The label a catalog gives one value of an enum attribute.

  The msgid is `"<attribute>.<value>"` — see `enum_msgid/2`. An uncovered value
  falls back to a humanized form of the value itself (`:awaiting_pickup` reads
  as `"Awaiting pickup"`), because the alternative is putting `status.awaiting_pickup`
  in front of a user. The fallback is a stopgap that keeps a screen readable, not
  a substitute for the catalog entry — use `fetch_enum_label/5` to assert coverage.

  Nothing here touches the attribute or its `Ash.Type.Enum`: this is a function
  a caller uses where they already render, not a change to a resource.
  """
  @spec enum_label(backend(), text_domain(), msgid(), msgid(), locale()) :: String.t()
  def enum_label(backend, text_domain, attribute, value, locale) do
    backend
    |> fetch_enum_label(text_domain, attribute, value, locale)
    |> string()
  end

  @doc """
  The label for an enum value, reporting whether the catalog covered it.
  """
  @spec fetch_enum_label(backend(), text_domain(), msgid(), msgid(), locale()) ::
          {:ok, String.t()} | {:missing, String.t()}
  def fetch_enum_label(backend, text_domain, attribute, value, locale) do
    case fetch(backend, text_domain, enum_msgid(attribute, value), [], locale) do
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

  defp string({:ok, translated}), do: translated
  defp string({:missing, fallback}), do: fallback

  defp classify(translated, msgids) do
    if translated in msgids, do: {:missing, translated}, else: {:ok, translated}
  end

  # Gettext's runtime entry points are reached through apply/3 so the compiler
  # treats the msgid as data. Calling them directly makes gettext's extraction
  # macros try to record a msgid that is only known at runtime.
  defp lookup(entry_point, args) do
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
