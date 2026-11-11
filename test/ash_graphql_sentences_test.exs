defmodule AshGettext.AshGraphqlSentencesTest do
  @moduledoc """
  AshGraphql writes a fixed sentence for some of Ash's errors. Each one has to
  be listed in `AshGettext.AshMessages`, or `mix gettext.extract` never shows
  it to a translator and readers get it in English.

  This reads AshGraphql's source, so it fails here, in this library, the day
  an AshGraphql update adds a sentence. An app that uses the library is not
  affected: a sentence nobody listed goes out as AshGraphql wrote it.
  """

  use ExUnit.Case, async: true

  @translated_by_error_code ["forbidden"]
  @written_for_ash_authentication [
    "Authentication failed",
    "An invalid token was presented",
    "Invalid token"
  ]

  defp sentences_ash_graphql_writes do
    source =
      Mix.Project.deps_paths()
      |> Map.fetch!(:ash_graphql)
      |> Path.join("lib/error.ex")
      |> File.read!()

    ~r/(?:message|short_message):\s*"([^"#]+)"/
    |> Regex.scan(source, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  test "AshGraphql's source is still read the way this test expects" do
    assert "is required" in sentences_ash_graphql_writes()
  end

  test "every sentence AshGraphql writes for an Ash error is listed for translators" do
    listed =
      AshGettext.AshMessages.msgids() ++
        @translated_by_error_code ++ @written_for_ash_authentication

    assert sentences_ash_graphql_writes() -- listed == []
  end
end
