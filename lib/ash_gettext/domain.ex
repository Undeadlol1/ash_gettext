defmodule AshGettext.Domain do
  @moduledoc """
  Declares, once per Ash domain, how this application translates.

      defmodule MyApp.Shop do
        use Ash.Domain, extensions: [AshGettext.Domain]

        gettext do
          backend MyApp.Gettext
          default_locale "en"
          text_domain "errors"
          locale_resolvers [MyApp.Localization.Adapter, AshGettext.Locale.Context]
        end

        resources do
          resource MyApp.Shop.Order
        end
      end

  Configuration lives here rather than in `config.exs` on purpose. Ash configures
  through DSL and passes request-scoped data through action context; global
  application env would be process-wide mutable state, which forces
  `Application.put_env` in tests and rules out `async: true`. Everything here is
  read back through `AshGettext.Info`.

  The supported locale list is deliberately *not* an option — it is derived from
  the backend via `AshGettext.known_locales/1`, so it cannot drift from the
  catalogs actually on disk.

  Repeating this block across many domains is avoided the same way Ash avoids it
  elsewhere: put it in a base domain macro and `use` that instead.
  """

  @gettext %Spark.Dsl.Section{
    name: :gettext,
    describe: "Configure how this domain translates user-facing strings.",
    examples: [
      """
      gettext do
        backend MyApp.Gettext
        default_locale "en"
        text_domain "errors"
      end
      """
    ],
    schema: [
      backend: [
        type: :atom,
        required: true,
        doc: "The Gettext backend whose catalogs this domain translates against."
      ],
      default_locale: [
        type: :string,
        default: "en",
        doc: "The locale used when no resolver has an opinion."
      ],
      text_domain: [
        type: :string,
        default: "errors",
        doc: "The gettext text domain error messages are looked up in."
      ],
      locale_resolvers: [
        type: {:list, {:behaviour, AshGettext.Locale.Resolver}},
        default: [AshGettext.Locale.Context],
        doc: """
        Modules implementing `AshGettext.Locale.Resolver`, tried in order until one
        answers. Host-specific resolvers (\"read the user's stored locale\") belong
        here; the library ships only the generic ones.
        """
      ],
      translate_errors?: [
        type: :boolean,
        default: true,
        doc: "Whether resources in this domain translate their action errors."
      ]
    ]
  }
  use Spark.Dsl.Extension, sections: [@gettext]
end
