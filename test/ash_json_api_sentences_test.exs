defmodule AshGettext.AshJsonApiSentencesTest do
  @moduledoc """
  AshJsonApi writes a fixed sentence for some of Ash's errors. Each one has to
  be listed in `AshGettext.AshMessages`, or `mix gettext.extract` never shows
  it to a translator and readers get it in English.

  This reads AshJsonApi's source, so it fails here, in this library, the day
  an AshJsonApi update adds a sentence. An app that uses the library is not
  affected: a sentence nobody listed goes out as AshJsonApi wrote it.
  """

  use ExUnit.Case, async: true

  @translated_by_error_code ["forbidden"]

  defp sentences_ash_json_api_writes do
    source =
      Mix.Project.deps_paths()
      |> Map.fetch!(:ash_json_api)
      |> Path.join("lib/ash_json_api/error/error.ex")
      |> File.read!()

    ~r/detail:\s*"([^"#]+)"/
    |> Regex.scan(source, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  test "AshJsonApi's source is still read the way this test expects" do
    assert "is required" in sentences_ash_json_api_writes()
  end

  test "every sentence AshJsonApi writes for an Ash error is listed for translators" do
    listed = AshGettext.AshMessages.msgids() ++ @translated_by_error_code

    assert sentences_ash_json_api_writes() -- listed == []
  end
end
