defmodule AshGettext.MixProject do
  use Mix.Project

  @source_url "https://github.com/Undeadlol1/ash_gettext"
  @version "0.1.0"

  def project do
    [
      app: :ash_gettext,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      docs: &docs/0,
      description: description(),
      package: package(),
      name: "AshGettext",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.32"},
      {:spark, "~> 2.3"},
      {:gettext, "~> 1.0"},
      {:telemetry, "~> 1.1"},
      {:ash_json_api, "~> 1.4", optional: true},
      {:plug, "~> 1.14", optional: true},
      {:ash_phoenix, "~> 2.3", only: :test},
      # AshJsonApi needs it to serve a POST route in the HTTP tests.
      {:open_api_spex, "~> 3.16", only: :test},
      # Ash needs a SAT solver to check the policy in the HTTP tests.
      {:simple_sat, "~> 0.1", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # Only for `mix spark.cheat_sheets`, which generates the DSL reference.
      {:igniter, "~> 0.6", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "spark.cheat_sheets":
        "spark.cheat_sheets --extensions AshGettext.Domain,AshGettext.Resource",
      docs: ["spark.cheat_sheets", "docs"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        {"README.md", title: "Home"},
        "documentation/topics/set-up-once.md",
        "documentation/topics/translating-text.md",
        "documentation/topics/locales.md",
        "documentation/topics/translating-errors.md",
        "documentation/topics/extracting-messages.md",
        "documentation/topics/testing.md",
        "documentation/topics/how-it-works.md",
        {"documentation/dsls/DSL-AshGettext.Domain.md",
         search_data: Spark.Docs.search_data_for(AshGettext.Domain)},
        {"documentation/dsls/DSL-AshGettext.Resource.md",
         search_data: Spark.Docs.search_data_for(AshGettext.Resource)},
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Topics: ~r"documentation/topics",
        Reference: ~r"documentation/dsls",
        "About AshGettext": ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        "Public API": [
          AshGettext,
          AshGettext.Enum,
          AshGettext.Domain,
          AshGettext.Resource,
          AshGettext.Error
        ],
        Locales: [
          AshGettext.Locale.Resolver,
          AshGettext.Locale.Normalizer
        ],
        "How it works": [
          AshGettext.Info,
          AshGettext.ErrorTranslation,
          AshGettext.ErrorTranslation.ErrorHandler,
          AshGettext.AshMessages,
          AshGettext.JsonApi,
          AshGettext.Plug,
          AshGettext.Extractor,
          AshGettext.Installer,
          AshGettext.Resource.Transformers.AttachErrorHandler,
          AshGettext.Domain.Transformers.MarkTexts,
          AshGettext.Domain.Transformers.TranslateJsonApiReplies,
          AshGettext.Domain.Verifiers.ValidateResourceExtensions
        ],
        "Mix tasks": [Mix.Tasks.AshGettext.Install]
      ]
    ]
  end

  defp description do
    "Translations for Ash apps, with Gettext. Your text, your enum values and " <>
      "Ash's error messages come out in each user's language."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib documentation .formatter.exs mix.exs README.md CHANGELOG.md LICENSE usage-rules.md)
    ]
  end
end
