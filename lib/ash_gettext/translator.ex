defmodule AshGettext.Translator do
  @moduledoc """
  One module that knows your backend and the user's language, so a call site
  only says what to translate.

      defmodule MyApp.Translator do
        use AshGettext.Translator,
          backend: MyApp.Gettext,
          locale_resolvers: [MyApp.Locale.FromActor, AshGettext.Locale.FromContext],
          default_locale: "en"
      end

      MyApp.Translator.translate("Order shipped", [], actor: user)
      MyApp.Translator.translate_plural("%{count} item", "%{count} items", 3)
      MyApp.Translator.locale(locale: "ru_RU")
      #=> "ru"

  ## `use` options

    * `:backend` - required; your Gettext backend.
    * `:locale_resolvers` - modules implementing `AshGettext.Locale.Resolver`.
      Defaults to `[AshGettext.Locale.FromContext]`.
    * `:default_locale` - used when no resolver answers. Defaults to the
      backend's source locale.

  ## Call options

    * `:locale` - an explicit locale; wins over the resolvers.
    * `:actor` - handed to the resolvers as `:actor`.
    * `:context` - a map merged into the resolver context.
    * `:text_domain` - defaults to `"default"`.

  A resolver must be a pure function of its context: read the locale off the
  loaded actor, do not query a database.

  The generated functions delegate to this module's functions, which take the
  config as their first argument.
  """

  @use_options [:backend, :locale_resolvers, :default_locale]

  defmacro __using__(opts) do
    validate_use_options!(opts)

    quote do
      @doc "The locale for the given options (see `AshGettext.Translator`)."
      def locale(opts \\ []), do: AshGettext.Translator.locale(__ash_gettext_config__(), opts)

      @doc "Translate `msgid` (see `AshGettext.Translator`)."
      def translate(msgid, bindings \\ [], opts \\ []),
        do: AshGettext.Translator.translate(__ash_gettext_config__(), msgid, bindings, opts)

      @doc "Translate a pluralised `msgid` (see `AshGettext.Translator`)."
      def translate_plural(msgid, msgid_plural, count, bindings \\ [], opts \\ []) do
        AshGettext.Translator.translate_plural(
          __ash_gettext_config__(),
          msgid,
          msgid_plural,
          count,
          bindings,
          opts
        )
      end

      defp __ash_gettext_config__, do: unquote(opts)
    end
  end

  @doc "The locale for `opts`, resolved against `config`."
  @spec locale(keyword(), keyword()) :: String.t()
  def locale(config, opts) do
    backend = Keyword.fetch!(config, :backend)

    given = Map.reject(%{locale: opts[:locale], actor: opts[:actor]}, fn {_k, v} -> is_nil(v) end)
    context = opts |> Keyword.get(:context, %{}) |> Map.merge(given)

    # An explicit locale wins: only the context reader looks at it.
    resolvers =
      if opts[:locale],
        do: [AshGettext.Locale.FromContext],
        else: Keyword.get(config, :locale_resolvers, [AshGettext.Locale.FromContext])

    AshGettext.Locale.resolve(context,
      resolvers: resolvers,
      supported: AshGettext.known_locales(backend),
      default: Keyword.get(config, :default_locale) || AshGettext.source_locale(backend)
    )
  end

  @doc "Translate `msgid` in the locale `opts` resolve to."
  @spec translate(keyword(), AshGettext.msgid(), AshGettext.bindings(), keyword()) :: String.t()
  def translate(config, msgid, bindings, opts) do
    AshGettext.translate(
      Keyword.fetch!(config, :backend),
      Keyword.get(opts, :text_domain, "default"),
      msgid,
      bindings,
      locale(config, opts)
    )
  end

  @doc "Translate a pluralised `msgid` in the locale `opts` resolve to."
  @spec translate_plural(
          keyword(),
          AshGettext.msgid(),
          AshGettext.msgid(),
          non_neg_integer(),
          AshGettext.bindings(),
          keyword()
        ) :: String.t()
  def translate_plural(config, msgid, msgid_plural, count, bindings, opts) do
    AshGettext.translate_plural(
      Keyword.fetch!(config, :backend),
      Keyword.get(opts, :text_domain, "default"),
      msgid,
      msgid_plural,
      count,
      bindings,
      locale(config, opts)
    )
  end

  defp validate_use_options!(opts) do
    unless Keyword.keyword?(opts) and Keyword.has_key?(opts, :backend) do
      raise ArgumentError, "use AshGettext.Translator requires a :backend option"
    end

    case Keyword.keys(opts) -- @use_options do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown option(s) #{inspect(unknown)} for use AshGettext.Translator; " <>
                "expected #{inspect(@use_options)}"
    end
  end
end
