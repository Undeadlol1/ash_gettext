defmodule AshGettext.Locale do
  @moduledoc """
  The single "what language is this?" entry point.

  Resolvers are tried in order and the first one with an opinion wins; when none
  has one, the default applies. The answer is always normalised against the
  locales the catalogs actually ship, so a caller can never end up asking gettext
  for a language that does not exist.

  Everything is an argument. There is no `Application.get_env` here and no
  process dictionary, which is what lets every test that touches locale run
  `async: true`.

      AshGettext.Locale.resolve(%{locale: "ru_RU"},
        resolvers: [AshGettext.Locale.Context],
        supported: ["en", "ru"],
        default: "en"
      )
      #=> "ru"

  Once the domain DSL lands (`AshGettext.Domain`, step 2), the host will declare
  its resolvers once per domain and these options will be read from there via
  `AshGettext.Info` — still not from global config.
  """

  alias AshGettext.Locale.Normalizer

  @type option ::
          {:resolvers, [module()]}
          | {:supported, [String.t()]}
          | {:default, String.t()}

  @doc """
  Resolve the locale for `context`.

  ## Options

    * `:default` — required; the locale to use when nothing else answers.
    * `:resolvers` — modules implementing `AshGettext.Locale.Resolver`, tried in
      order. Defaults to `[AshGettext.Locale.Context]`.
    * `:supported` — the locales the catalogs cover. Defaults to `[default]`.
      Pass `AshGettext.known_locales(backend)` to derive it from the backend.
  """
  @spec resolve(map(), [option()]) :: String.t()
  def resolve(context, opts) when is_map(context) do
    default = Keyword.fetch!(opts, :default)
    resolvers = Keyword.get(opts, :resolvers, [AshGettext.Locale.Context])
    supported = Keyword.get(opts, :supported, [default])

    resolvers
    |> first_opinion(context)
    |> Normalizer.normalize(supported, default)
  end

  defp first_opinion(resolvers, context) do
    Enum.find_value(resolvers, fn resolver -> resolver.resolve(context) end)
  end
end
