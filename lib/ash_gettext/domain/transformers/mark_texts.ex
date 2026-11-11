defmodule AshGettext.Domain.Transformers.MarkTexts do
  @moduledoc """
  Shows `mix gettext.extract` every text this domain's resources translate:
  written attribute labels, literal `message`s in their DSL and in the app's
  own validation, change and preparation modules they use, every literal
  `message:` in the app's own source (`extract_messages_from`) go to
  `text_domain`. The sentences Ash ships in its own template and the ones for
  Ash's errors that have no message (`AshGettext.AshMessages`) go to
  `builtin_text_domain`, once per backend. See `AshGettext.Extractor`.

  It runs in the domain, not the resource: an Ash domain compiles its
  resources first, so a resource waiting on its domain would deadlock.
  Messages are left out when the domain sets `translate_errors? false`. It
  only does work while Gettext is extracting, so a normal compile is unchanged.
  """

  use Spark.Dsl.Transformer

  alias AshGettext.Extractor
  alias Spark.Dsl.Transformer

  @doc false
  def after?(_transformer), do: true

  @doc false
  def transform(dsl_state) do
    backend = Transformer.get_option(dsl_state, [:gettext], :backend)

    if backend && Gettext.Extractor.extracting?(),
      do: {:ok, mark(dsl_state, backend)},
      else: {:ok, dsl_state}
  end

  defp mark(dsl_state, backend) do
    text_domain = Transformer.get_option(dsl_state, [:gettext], :text_domain, "ash")
    errors? = Transformer.get_option(dsl_state, [:gettext], :translate_errors?, true)

    folders = Transformer.get_option(dsl_state, [:gettext], :extract_messages_from, ["lib"])

    {scan_is, scan} =
      if errors? and folders != [],
        do: Extractor.app_messages(backend, text_domain, folders),
        else: {:seen, %{paths: MapSet.new(), messages: []}}

    scanned = MapSet.new(scan.messages, &{&1.msgid, &1.path})

    texts =
      for %{resource: resource} <- Transformer.get_entities(dsl_state, [:resources]),
          Code.ensure_compiled(resource) == {:module, resource},
          AshGettext.Resource in Spark.extensions(resource),
          text <- Extractor.resource_messages(resource, errors?, scan.paths),
          not MapSet.member?(scanned, {text.msgid, text.path}),
          do: text

    texts = if scan_is == :new, do: scan.messages ++ texts, else: texts

    builtin_text_domain =
      Transformer.get_option(dsl_state, [:gettext], :builtin_text_domain, "ash_builtin")

    builtin = if errors?, do: Extractor.builtin_messages(backend, builtin_text_domain), else: []

    Transformer.eval(
      dsl_state,
      [],
      quote do
        Extractor.mark(
          __ENV__,
          unquote(backend),
          unquote(text_domain),
          unquote(Macro.escape(texts))
        )

        Extractor.mark(
          __ENV__,
          unquote(backend),
          unquote(builtin_text_domain),
          unquote(Macro.escape(builtin))
        )
      end
    )
  end
end
