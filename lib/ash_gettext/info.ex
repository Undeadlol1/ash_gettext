defmodule AshGettext.Info do
  @moduledoc """
  Read a domain's `gettext do ... end` configuration.

  `Spark.InfoGenerator` supplies the per-option readers — `gettext_backend/1`,
  `gettext_default_locale/1`, `gettext_text_domain/1`, `gettext_locale_resolver/1`,
  `gettext_translate_errors?/1` — each returning `{:ok, value}` or `:error`, plus
  raising `!` variants.

  On top of those, `settings/1` answers the one question every caller actually
  has: *is this domain set up to translate, and with what?*
  """

  use Spark.InfoGenerator, extension: AshGettext.Domain, sections: [:gettext]

  require Logger

  @typedoc "Everything needed to translate for a domain."
  @type settings :: %{
          backend: module(),
          default_locale: String.t(),
          text_domain: String.t(),
          locale_resolver: module() | nil,
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
    if translating?(domain), do: locale_settings(domain), else: :error
  end

  @doc """
  The domain's gettext settings, whether or not error translation is on.

  `:error` only when the domain has no `gettext` block. Used to find the
  backend, text domain and language rules for enums, attributes and the
  action's language.
  """
  @spec locale_settings(module() | map()) :: {:ok, settings()} | :error
  def locale_settings(domain) do
    case gettext_backend(domain) do
      {:ok, backend} ->
        {:ok,
         %{
           backend: backend,
           default_locale: gettext_default_locale!(domain),
           text_domain: gettext_text_domain!(domain),
           locale_resolver: Spark.Dsl.Extension.get_opt(domain, [:gettext], :locale_resolver),
           supported_locales: AshGettext.known_locales(backend)
         }}

      :error ->
        :error
    end
  rescue
    # A domain without the extension has no such option.
    _no_extension -> :error
  end

  @doc """
  The `{backend, locale}` to use for `actor`, or `nil` for Gettext's current language.

  Asks the domain's `locale_resolver` with the actor and fits the answer to the
  catalogs. `nil` when there is no actor or the resolver returns
  `nil`. Nothing here changes the process language.
  """
  @spec language(module() | map(), term()) :: {module(), String.t()} | nil
  def language(_domain, nil), do: nil

  def language(domain, actor) do
    with {:ok, %{locale_resolver: resolver} = settings} when resolver != nil <-
           locale_settings(domain),
         answer when is_binary(answer) <- resolve(resolver, actor) do
      {settings.backend,
       AshGettext.Locale.Normalizer.normalize(
         answer,
         settings.supported_locales,
         settings.default_locale
       )}
    else
      _no_answer -> nil
    end
  end

  defp resolve(resolver, actor) do
    resolver.resolve(actor)
  rescue
    exception -> failed(resolver, Exception.format_banner(:error, exception))
  catch
    kind, reason -> failed(resolver, Exception.format_banner(kind, reason))
  end

  defp failed(resolver, reason) do
    Logger.warning("#{inspect(resolver)} could not resolve a locale: #{reason}")
    nil
  end

  @doc """
  The locale to answer `actor` in: the one `language/2` gives, else `backend`'s
  current language.
  """
  @spec locale(module() | map(), term(), module()) :: String.t()
  def locale(domain, actor, backend) do
    case language(domain, actor) do
      {_backend, locale} -> locale
      nil -> Gettext.get_locale(backend)
    end
  end

  @doc """
  The written label of a resource's attribute from its `gettext` block, or `nil`.
  """
  @spec attribute_label(module(), atom()) :: String.t() | nil
  def attribute_label(resource, attribute) do
    resource
    |> Spark.Dsl.Extension.get_entities([:gettext])
    |> Enum.find_value(&(&1.attribute == attribute && &1.text))
  end

  @doc """
  Every written attribute label of a resource, as `{attribute, text}`.
  """
  @spec attribute_labels(module()) :: [{atom(), String.t()}]
  def attribute_labels(resource) do
    resource
    |> Spark.Dsl.Extension.get_entities([:gettext])
    |> Enum.map(&{&1.attribute, &1.text})
  end

  defp translating?(domain) do
    gettext_translate_errors?(domain)
  rescue
    # A domain without the extension has no such option; that is a plain "no",
    # not an error worth surfacing to a caller mid-request.
    _no_extension -> false
  end
end
