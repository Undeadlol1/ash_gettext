defmodule AshGettext.Locale.Normalizer do
  @moduledoc """
  Reduce a locale as it arrives in the wild to one the catalogs actually have.

  Clients send `ru_RU`, `en-US`, `ru`, or nothing at all. Catalogs are keyed by
  the language subtag. This module is the single place that reconciles the two,
  so no call site has to decide what `en_KZ` means.
  """

  @doc """
  Reduce `locale` to a supported locale, or `default` when it maps to none.

      iex> AshGettext.Locale.Normalizer.normalize("ru_RU", ["en", "ru"], "en")
      "ru"

      iex> AshGettext.Locale.Normalizer.normalize("de", ["en", "ru"], "en")
      "en"

      iex> AshGettext.Locale.Normalizer.normalize(nil, ["en", "ru"], "en")
      "en"
  """
  @spec normalize(String.t() | nil, [String.t()], String.t()) :: String.t()
  def normalize(nil, _supported, default), do: default

  def normalize(locale, supported, default) when is_binary(locale) do
    language = language_subtag(locale)

    if language in supported, do: language, else: default
  end

  @doc """
  Strip the region and script from `locale`, leaving the language subtag.

      iex> AshGettext.Locale.Normalizer.language_subtag("en-US")
      "en"
  """
  @spec language_subtag(String.t()) :: String.t()
  def language_subtag(locale) when is_binary(locale) do
    locale
    |> String.split(["-", "_"], parts: 2)
    |> List.first()
  end
end
