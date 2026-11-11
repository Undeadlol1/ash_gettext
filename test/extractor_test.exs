defmodule AshGettext.ExtractorTest do
  use ExUnit.Case, async: true

  alias AshGettext.Extractor

  defp find_messages(source), do: Extractor.find_messages([{"lib/sample.ex", source}])

  describe "finding messages written as keyword options" do
    test "finds a message given as a keyword option" do
      result =
        find_messages("""
        defmodule Sample do
          def validate(_), do: {:error, field: :weight, message: "must be at least 30 kg"}
        end
        """)

      assert [%{msgid: "must be at least 30 kg"}] = result.messages
    end

    test "records where the message was found" do
      result =
        find_messages("""
        defmodule Sample do
          def validate(_) do
            {:error, message: "not allowed"}
          end
        end
        """)

      assert [%{references: [%{path: "lib/sample.ex", line: 3}]}] = result.messages
    end

    test "finds a message nested inside a DSL block" do
      result =
        find_messages("""
        defmodule Sample do
          identities do
            identity :one_per_type, [:user_id] do
              message "A streak of this type already exists"
            end
          end
        end
        """)

      assert [%{msgid: "A streak of this type already exists"}] = result.messages
    end
  end

  describe "merging repeated messages" do
    test "collapses the same msgid into one entry with every reference" do
      result =
        Extractor.find_messages([
          {"lib/a.ex", ~s|def a, do: [message: "cannot be blank"]|},
          {"lib/b.ex", ~s|def b, do: [message: "cannot be blank"]|}
        ])

      assert [%{msgid: "cannot be blank", references: references}] = result.messages
      assert Enum.map(references, & &1.path) == ["lib/a.ex", "lib/b.ex"]
    end

    test "sorts messages by msgid so the template is stable across runs" do
      result =
        find_messages("""
        defmodule Sample do
          def a, do: [message: "zebra"]
          def b, do: [message: "apple"]
        end
        """)

      assert Enum.map(result.messages, & &1.msgid) == ["apple", "zebra"]
    end
  end

  describe "skipping messages that cannot be msgids" do
    test "reports an interpolated message instead of extracting it" do
      result =
        find_messages("""
        defmodule Sample do
          def a(value), do: [message: "Unable to parse: \#{inspect(value)}"]
        end
        """)

      assert result.messages == []
      assert [%{path: "lib/sample.ex", line: 2}] = result.interpolated
    end

    test "ignores a message whose value is a variable" do
      result =
        find_messages("""
        defmodule Sample do
          def a(text), do: [message: text]
        end
        """)

      assert result.messages == []
      assert result.interpolated == []
    end
  end

  describe "surviving files that do not parse" do
    test "skips a file that does not parse rather than crashing the run" do
      result = Extractor.find_messages([{"lib/broken.ex", "defmodule Broken do def ("}])

      assert result.messages == []
    end

    test "returns nothing for a file with no messages" do
      result = find_messages("defmodule Sample do\n  def a, do: :ok\nend\n")

      assert result.messages == []
    end
  end

  describe "following the modules a resource points at" do
    setup do
      %{texts: Extractor.resource_texts(ExtractorFixture.Parcel, true)}
    end

    test "reads the run module of a generic action", %{texts: texts} do
      assert "the run module refused" in texts
    end

    test "reads the module of a manual action", %{texts: texts} do
      assert "the manual action refused" in texts
    end

    test "reads the module of a calculation", %{texts: texts} do
      assert "the calculation refused" in texts
    end
  end
end
