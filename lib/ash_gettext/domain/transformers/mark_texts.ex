defmodule AshGettext.Domain.Transformers.MarkTexts do
  @moduledoc """
  Shows `mix gettext.extract` every text this domain's resources translate:
  written attribute labels, literal `message`s in their DSL and in the app's
  own validation, change and preparation modules they use, the sentences Ash
  ships in its own template, and the ones for Ash's errors that have no
  message (`AshGettext.AshMessages`). See `AshGettext.Extractor`.

  It runs in the domain, not the resource: an Ash domain compiles its
  resources first, so a resource waiting on its domain would deadlock.
  Messages are left out when the domain sets `translate_errors? false`. It
  only does work while Gettext is extracting, so a normal compile is unchanged.
  """

  use Spark.Dsl.Transformer

  alias AshGettext.AshMessages
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

    texts =
      for %{resource: resource} <- Transformer.get_entities(dsl_state, [:resources]),
          Code.ensure_compiled(resource) == {:module, resource},
          AshGettext.Resource in Spark.extensions(resource),
          text <- AshGettext.Extractor.resource_messages(resource, errors?),
          do: text

    texts =
      if errors?,
        do: texts ++ AshMessages.msgids() ++ AshMessages.ash_sentences(),
        else: texts

    Transformer.eval(
      dsl_state,
      [],
      quote do
        AshGettext.Extractor.mark(
          __ENV__,
          unquote(backend),
          unquote(text_domain),
          unquote(Macro.escape(texts))
        )
      end
    )
  end
end
