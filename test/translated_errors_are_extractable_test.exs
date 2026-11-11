defmodule AshGettext.TranslatedErrorsAreExtractableTest do
  @moduledoc """
  Every error text these tests translate must be a text `mix gettext.extract`
  finds. A text that is translated here but never reaches an app's template
  would stay in the source language for every real user.
  """

  use ExUnit.Case, async: true

  alias AshGettext.AshMessages
  alias AshGettext.Extractor

  @catalog "priv/test_gettext/ru/LC_MESSAGES/fixture.po"
  @not_error_texts [
    "greeting",
    "intake_added",
    "Order placed",
    "Ready for pickup",
    "On its way",
    "Ready at the pickup point"
  ]

  defp translated_in_the_catalog do
    for message <- Expo.PO.parse_file!(@catalog).messages,
        IO.iodata_to_binary(message.msgstr) != "",
        do: IO.iodata_to_binary(message.msgid)
  end

  defp fixture_domains do
    {:ok, modules} = :application.get_key(:ash_gettext, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :spark_is, 0),
        module.spark_is() == Ash.Domain,
        AshGettext.Domain in Spark.extensions(module),
        do: module
  end

  defp found_by_extraction do
    from_resources =
      for domain <- fixture_domains(),
          resource <- Ash.Domain.Info.resources(domain),
          AshGettext.Resource in Spark.extensions(resource),
          text <- Extractor.resource_texts(resource, true),
          do: text

    from_resources ++ AshMessages.msgids() ++ AshMessages.ash_sentences()
  end

  test "every error text the Russian catalog translates is found by extraction" do
    assert translated_in_the_catalog() -- (found_by_extraction() ++ @not_error_texts) == []
  end

  test "the catalog translates more than the texts that are not errors" do
    assert length(translated_in_the_catalog()) > length(@not_error_texts)
  end
end
