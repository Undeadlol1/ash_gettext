defmodule AshGettext.Locale.Normalizer do
  @moduledoc """
  Reduce a locale as it arrives in the wild to one the catalogs actually have.

  Clients send `ru_RU`, `en-US`, `ru`, or nothing at all. Catalogs are keyed by
  the language subtag, or by language and region. This module is the single place that reconciles the two,
  so no call site has to decide what `en_KZ` means.

  `AshGettext.Info.language/2` runs it on what the resolver returns.
  It runs on every translated error, so it does no I/O and keeps no state.
  A language the backend does not ship falls back to the default locale.
  """

  @doc """
  Reduce `locale` to a supported locale, or `default` when it maps to none.

  The whole locale is used when it is supported (`-` read as `_`), so
  `"pt-BR"` becomes `"pt_BR"` when that catalog exists. Otherwise the region
  and script are dropped, so `"ru_RU"` and `"ru-Cyrl"` both become `"ru"`.
  A `nil` locale returns `default`. The result is always a member of
  `supported` or `default` itself.

      iex> AshGettext.Locale.Normalizer.normalize("ru_RU", ["en", "ru"], "en")
      "ru"

      iex> AshGettext.Locale.Normalizer.normalize("de", ["en", "ru"], "en")
      "en"

      iex> AshGettext.Locale.Normalizer.normalize(nil, ["en", "ru"], "en")
      "en"

      iex> AshGettext.Locale.Normalizer.normalize("pt-BR", ["en", "pt", "pt_BR"], "en")
      "pt_BR"

      iex> AshGettext.Locale.Normalizer.normalize("pt_PT", ["en", "pt", "pt_BR"], "en")
      "pt"
  """
  @spec normalize(String.t() | nil, [String.t()], String.t()) :: String.t()
  def normalize(nil, _supported, default), do: default

  def normalize(locale, supported, default) when is_binary(locale) do
    whole = String.replace(locale, "-", "_")
    language = language_code(locale)

    cond do
      whole in supported -> whole
      language in supported -> language
      true -> default
    end
  end

  @doc """
  Strip the region and script from `locale`, leaving the language subtag.

      iex> AshGettext.Locale.Normalizer.language_code("en-US")
      "en"
  """
  @spec language_code(String.t()) :: String.t()
  def language_code(locale) when is_binary(locale) do
    locale
    |> String.split(["-", "_"], parts: 2)
    |> List.first()
  end
end
