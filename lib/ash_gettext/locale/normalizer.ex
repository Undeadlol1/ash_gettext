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

  Anything from the first `.` or `@` on is dropped (`pt_BR.UTF-8` is `pt_BR`).
  The rest is split on `-` and `_`. The longest run of parts is tried first,
  then one part fewer, down to the language alone, so `"zh-Hant-TW"` tries
  `zh_Hant_TW`, `zh_Hant`, then `zh`. Case is ignored and `-` counts as `_`.
  The result is spelled as in `supported`. If nothing matches, or the locale is
  `nil`, the result is `default`.

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

      iex> AshGettext.Locale.Normalizer.normalize("zh-Hant-TW", ["en", "zh", "zh_Hant"], "en")
      "zh_Hant"

      iex> AshGettext.Locale.Normalizer.normalize("PT-br", ["en", "pt_BR"], "en")
      "pt_BR"
  """
  @spec normalize(String.t() | nil, [String.t()], String.t()) :: String.t()
  def normalize(nil, _supported, default), do: default

  def normalize(locale, supported, default) when is_binary(locale) do
    parts =
      locale
      |> String.split([".", "@"], parts: 2)
      |> hd()
      |> String.split(["-", "_"], trim: true)

    parts
    |> length()
    |> Range.new(1, -1)
    |> Enum.find_value(default, fn count ->
      wanted = parts |> Enum.take(count) |> Enum.join("_") |> String.downcase()
      Enum.find(supported, &(&1 |> String.replace("-", "_") |> String.downcase() == wanted))
    end)
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
