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

  describe "writing the template" do
    test "renders a msgid with the file it comes from" do
      pot =
        Extractor.to_template([
          %{msgid: "cannot be blank", references: [%{path: "lib/a.ex", line: 7}]}
        ])

      assert pot =~ "#: lib/a.ex"
      assert pot =~ ~s|msgid "cannot be blank"|
      assert pot =~ ~s|msgstr ""|
    end

    test "leaves the line number out, so an edit above a message does not move the template" do
      early =
        Extractor.to_template([
          %{msgid: "cannot be blank", references: [%{path: "lib/a.ex", line: 7}]}
        ])

      later =
        Extractor.to_template([
          %{msgid: "cannot be blank", references: [%{path: "lib/a.ex", line: 991}]}
        ])

      assert early == later
    end

    test "names a file once even when it declares the same message twice" do
      pot =
        Extractor.to_template([
          %{
            msgid: "cannot be blank",
            references: [%{path: "lib/a.ex", line: 7}, %{path: "lib/a.ex", line: 42}]
          }
        ])

      assert pot |> String.split("#: lib/a.ex") |> length() == 2
    end

    test "escapes quotes so the template stays parseable" do
      pot = Extractor.to_template([%{msgid: ~s|say "hi"|, references: []}])

      assert pot =~ ~S|msgid "say \"hi\""|
    end

    test "escapes newlines rather than breaking the entry across lines" do
      pot = Extractor.to_template([%{msgid: "line one\nline two", references: []}])

      assert pot =~ ~S|msgid "line one\nline two"|
    end

    test "starts with a PO template header" do
      assert Extractor.to_template([]) =~ ~s|msgid ""|
    end
  end

  describe "messages for Ash's own errors" do
    test "lists every written sentence, naming the error it is for" do
      messages = Extractor.ash_messages()

      assert Enum.map(messages, & &1.msgid) == Enum.sort(AshGettext.AshMessages.msgids())

      assert %{comments: ["Ash.Error.Changes.Required"], references: []} =
               Enum.find(messages, &(&1.msgid == "is required"))
    end
  end

  describe "messages from resources" do
    test "lists only written texts, with where they come from" do
      messages = Extractor.resource_messages([AshGettextFixture.Parcel])

      assert Enum.map(messages, & &1.msgid) ==
               Enum.sort([
                 "Weight",
                 "Label",
                 "Past statuses",
                 "Order placed",
                 "Ready for pickup",
                 "Ready at the pickup point",
                 "On its way",
                 "Parcel lost"
               ])

      assert %{comments: ["AshGettextFixture.Parcel.weight"], references: []} =
               Enum.find(messages, &(&1.msgid == "Weight"))

      assert %{
               comments: [
                 "AshGettextFixture.Parcel.past_statuses",
                 "AshGettextFixture.Parcel.status"
               ]
             } =
               Enum.find(messages, &(&1.msgid == "Parcel lost"))
    end

    test "collects nothing from attributes and enums nobody wrote text for" do
      assert Extractor.resource_messages([AshGettextFixture.Untranslated.Parcel]) == []
      refute Enum.any?(Extractor.resource_messages([AshGettextFixture.Crate]), &(&1.msgid == "A"))
    end

    test "merging combines references and comments of one msgid" do
      merged =
        Extractor.merge([
          [%{msgid: "A", references: [%{path: "b.ex", line: 1}]}],
          [%{msgid: "A", references: [], comments: ["X.a"]}]
        ])

      assert [%{msgid: "A", references: [%{path: "b.ex"}], comments: ["X.a"]}] = merged
    end

    test "the template prints comments" do
      pot = Extractor.to_template([%{msgid: "A", references: [], comments: ["X.a"]}])
      assert pot =~ "#. X.a\nmsgid \"A\""
    end
  end
end
