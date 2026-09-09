defmodule AshGettext.Info do
  @moduledoc """
  Read a domain's `gettext do ... end` configuration.

  `Spark.InfoGenerator` supplies the per-option readers — `gettext_backend/1`,
  `gettext_default_locale/1`, `gettext_text_domain/1`, `gettext_locale_resolvers/1`,
  `gettext_translate_errors?/1` — each returning `{:ok, value}` or `:error`, plus
  raising `!` variants.

  On top of those, `settings/1` answers the one question every caller actually
  has: *is this domain set up to translate, and with what?*
  """

  use Spark.InfoGenerator, extension: AshGettext.Domain, sections: [:gettext]

  @typedoc "Everything needed to translate for a domain."
  @type settings :: %{
          backend: module(),
          default_locale: String.t(),
          text_domain: String.t(),
          locale_resolvers: [module()],
          supported_locales: [String.t()]
        }

  @doc """
  The domain's translation settings, or `:error` when it does not translate.

  Returns `:error` both for a domain without the `AshGettext.Domain` extension
  and for one that has explicitly set `translate_errors? false`, so a caller can
  treat "not configured" and "switched off" the same way — pass the value through
  untouched.
  """
  @spec settings(module() | map()) :: {:ok, settings()} | :error
  def settings(domain) do
    # `gettext_translate_errors?/1` is a predicate option, so Spark generates it
    # returning a bare boolean rather than the `{:ok, value}` the others use.
    with true <- translating?(domain),
         {:ok, backend} <- gettext_backend(domain) do
      {:ok,
       %{
         backend: backend,
         default_locale: gettext_default_locale!(domain),
         text_domain: gettext_text_domain!(domain),
         locale_resolvers: gettext_locale_resolvers!(domain),
         supported_locales: AshGettext.known_locales(backend)
       }}
    else
      _not_translating -> :error
    end
  end

  defp translating?(domain) do
    gettext_translate_errors?(domain)
  rescue
    # A domain without the extension has no such option; that is a plain "no",
    # not an error worth surfacing to a caller mid-request.
    _no_extension -> false
  end
end
