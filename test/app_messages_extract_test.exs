defmodule AshGettext.AppMessagesExtractTest do
  # Runs Gettext's own extractor, which is global state, so not async.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @fixture "test/support/scanned_fixture.ex"
  @heavy_check "test/support/scanned_fixture_heavy_check.ex"

  setup_all do
    normal_compile_warnings = capture_io(:stderr, fn -> Code.compile_file(@fixture) end)

    Gettext.Extractor.enable()

    extraction_warnings =
      try do
        capture_io(:stderr, fn -> Code.compile_file(@fixture) end)
      after
        Gettext.Extractor.disable()
      end

    %{
      pots: Gettext.Extractor.pot_files(:ash_gettext, []),
      normal_compile_warnings: normal_compile_warnings,
      extraction_warnings: extraction_warnings
    }
  end

  defp messages(pots, priv) do
    for {path, {_, contents}} <- pots,
        String.contains?(path, priv),
        {:ok, po} = contents |> IO.iodata_to_binary() |> Expo.PO.parse_string(),
        message <- po.messages,
        do: message
  end

  defp msgids(pots, priv), do: Enum.map(messages(pots, priv), &IO.iodata_to_binary(&1.msgid))

  defp references(pots, priv, msgid) do
    message = Enum.find(messages(pots, priv), &(IO.iodata_to_binary(&1.msgid) == msgid))
    List.flatten(message.references)
  end

  defp line_of(file \\ @fixture, snippet),
    do: Enum.find_index(String.split(File.read!(file), "\n"), &(&1 =~ snippet)) + 1

  defp interpolated_line, do: "#{@fixture}:#{line_of("Coins left")}"

  defp walked_interpolated_line, do: "#{@heavy_check}:#{line_of(@heavy_check, "too heavy: ")}"

  test "a message written in a plain module, at its own line", %{pots: pots} do
    assert references(pots, "scanned_fixture/shared", "Not enough coins") == [
             {@fixture, line_of(~s|message: "Not enough coins"|)}
           ]
  end

  test "a message both scanned and walked has one reference", %{pots: pots} do
    assert references(pots, "scanned_fixture/shared", "scanned and walked") == [
             {@fixture, line_of(~s|message: "scanned and walked"|)}
           ]
  end

  test "an interpolated message in a plain module is skipped silently", %{
    extraction_warnings: warnings
  } do
    refute warnings =~ interpolated_line()
  end

  test "an interpolated message in a module a resource names is warned about once", %{
    extraction_warnings: warnings
  } do
    occurrences = warnings |> String.split(walked_interpolated_line()) |> length()

    assert occurrences == 2
  end

  test "a domain that translates no errors scans nothing", %{pots: pots} do
    quiet = msgids(pots, "scanned_fixture/quiet")

    assert "Quiet weight" in quiet
    refute "Not enough coins" in quiet
    refute Enum.any?(pots, fn {path, _} -> path =~ "scanned_fixture/quiet/ash_builtin.pot" end)
  end

  test "built-in sentences go to the built-in catalog only", %{pots: pots} do
    assert "must be present" in msgids(pots, "scanned_fixture/shared/ash_builtin.pot")
    refute "must be present" in msgids(pots, "scanned_fixture/shared/ash.pot")
  end

  test "a domain with the scan off keeps only its resources' texts", %{pots: pots} do
    no_scan = msgids(pots, "scanned_fixture/no_scan")

    assert "walked, not scanned" in no_scan
    refute "Not enough coins" in no_scan
  end

  test "a message in a folder the domain does not list is not extracted", %{pots: pots} do
    default = msgids(pots, "scanned_fixture/default")

    assert "walked, default folders" in default
    refute "Not enough coins" in default
  end

  test "the folders scanned default to lib" do
    assert Spark.Dsl.Extension.get_opt(ScannedFixture.Default, [:gettext], :extract_messages_from) ==
             ["lib"]
  end

  test "an empty folder list extracts nothing from plain modules", %{pots: pots} do
    refute "Not enough coins" in msgids(pots, "scanned_fixture/no_scan")
  end

  test "a normal compile scans nothing", %{normal_compile_warnings: warnings} do
    refute warnings =~ interpolated_line()
  end
end
