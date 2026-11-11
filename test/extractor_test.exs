defmodule AshGettext.ExtractorTest do
  use ExUnit.Case, async: true

  alias AshGettext.Extractor

  defp find_messages(source), do: Extractor.find_messages([{"lib/sample.ex", source}])

  describe "the place a Spark annotation names" do
    test "a file Spark recorded as a binary" do
      anno = :erl_anno.set_file("lib/parcel.ex", :erl_anno.new(7))

      assert Extractor.anno_location(anno) == {"lib/parcel.ex", 7}
    end

    test "a file Spark recorded as a charlist" do
      anno = :erl_anno.set_file(~c"lib/parcel.ex", :erl_anno.new(7))

      assert Extractor.anno_location(anno) == {"lib/parcel.ex", 7}
    end

    test "an annotation without a file" do
      assert Extractor.anno_location(:erl_anno.new(7)) == nil
    end
  end

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

  describe "extracting the text the runtime sees" do
    test "unescapes a quote" do
      result = find_messages(~S|def a, do: [message: "must be \"x\""]|)

      assert [%{msgid: ~S|must be "x"|}] = result.messages
    end

    test "unescapes a newline and a unicode escape" do
      result = find_messages(~S|def a, do: [message: "one\ntwo \u00e9"]|)

      assert [%{msgid: "one\ntwo é"}] = result.messages
    end

    test "keeps a heredoc message as the runtime string" do
      result =
        find_messages(~S'''
        defmodule Sample do
          def a do
            [message: """
            first line
            second "line"
            """]
          end
        end
        ''')

      assert [%{msgid: "first line\nsecond \"line\"\n"}] = result.messages
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

    test "the app scan skips a file that is not UTF-8 or does not parse" do
      dir = Path.join(["tmp", inspect(__MODULE__), "unreadable_sources"])
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "latin1.ex"), <<"defmodule L do\n  @x \"", 255, "\"\nend\n">>)
      File.write!(Path.join(dir, "broken.ex"), ~s|defmodule B do\n  [message: "is broken"\n|)
      File.write!(Path.join(dir, "fine.ex"), ~s|defmodule F do\n  @x [message: "found"]\nend\n|)

      assert {_new_or_seen, %{messages: messages}} =
               Extractor.app_messages(__MODULE__.UnreadableSources, "ash", [dir])

      assert Enum.map(messages, & &1.msgid) == ["found"]
    end

    test "the app scan reads each folder list a domain names, for the same backend" do
      root = Path.join(["tmp", inspect(__MODULE__), "folder_sets"])
      File.rm_rf!(root)
      File.mkdir_p!(Path.join(root, "first"))
      File.mkdir_p!(Path.join(root, "second"))
      File.write!(Path.join([root, "first", "a.ex"]), ~s|@x [message: "in first"]\n|)
      File.write!(Path.join([root, "second", "b.ex"]), ~s|@x [message: "in second"]\n|)
      backend = __MODULE__.FolderSets

      assert {:new, first} = Extractor.app_messages(backend, "ash", [Path.join(root, "first")])
      assert {:new, second} = Extractor.app_messages(backend, "ash", [Path.join(root, "second")])

      assert Enum.map(first.messages, & &1.msgid) == ["in first"]
      assert Enum.map(second.messages, & &1.msgid) == ["in second"]
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

  describe "modules from a sibling app outside the working directory" do
    test "reads the messages of a validation module compiled elsewhere" do
      dir = Path.join(System.tmp_dir!(), "sibling_app_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      source = Path.join(dir, "sibling.ex")

      File.write!(source, """
      defmodule SiblingApp.Rule do
        use Ash.Resource.Validation

        @impl true
        def validate(_changeset, _opts, _context), do: {:error, message: "the sibling refused"}
      end

      defmodule SiblingApp.Parcel do
        use Ash.Resource, domain: SiblingApp.Domain, data_layer: Ash.DataLayer.Ets

        actions do
          create :create do
            validate SiblingApp.Rule
          end
        end

        attributes do
          uuid_primary_key :id
        end
      end

      defmodule SiblingApp.Domain do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource SiblingApp.Parcel
        end
      end
      """)

      ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.compile_file(source) end)

      assert "the sibling refused" in Extractor.resource_texts(SiblingApp.Parcel, true)
    end
  end
end
