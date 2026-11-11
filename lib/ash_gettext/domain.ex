defmodule AshGettext.Domain do
  @moduledoc """
  Declares, once per Ash domain, how its action errors are translated.

      defmodule MyApp.Shop do
        use Ash.Domain, extensions: [AshGettext.Domain]

        gettext do
          backend MyApp.Gettext
          default_locale "en"
          text_domain "ash"
          locale_resolver MyApp.Locale
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
    describe: "Configure how the errors of this domain's actions are translated.",
    examples: [
      """
      gettext do
        backend MyApp.Gettext
        default_locale "en"
        text_domain "ash"
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
        doc: "The locale used when the resolver names a language the catalogs do not have."
      ],
      text_domain: [
        type: :string,
        default: "ash",
        doc:
          "The gettext text domain for everything Ash-derived: errors, enum labels, attribute names."
      ],
      locale_resolver: [
        type: {:behaviour, AshGettext.Locale.Resolver},
        required: true,
        doc: """
        Required. A module implementing `AshGettext.Locale.Resolver`. It reads the
        language from the action's actor. With no actor, Gettext's current process
        language is used.
        """
      ],
      translate_errors?: [
        type: :boolean,
        default: true,
        doc: "Whether resources in this domain translate their action errors."
      ],
      require_resource_extension?: [
        type: :boolean,
        default: false,
        doc: """
        When true, compiling the domain reports every resource in its `resources`
        block that lacks the `AshGettext.Resource` extension (a compiler warning,
        an error under `--warnings-as-errors`). Off by default on purpose: Ash
        extensions are opted into, never imposed.
        """
      ]
    ]
  }
  use Spark.Dsl.Extension,
    sections: [@gettext],
    verifiers: [AshGettext.Domain.Verifiers.ValidateResourceExtensions],
    transformers: [
      AshGettext.Domain.Transformers.MarkTexts,
      AshGettext.Domain.Transformers.TranslateReplies
    ]
end
