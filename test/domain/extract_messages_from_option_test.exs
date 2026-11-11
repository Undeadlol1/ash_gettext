defmodule AshGettext.Domain.ExtractMessagesFromOptionTest do
  use ExUnit.Case, async: true

  defp compile_domain(name, folders) do
    Code.compile_string("""
    defmodule #{name} do
      use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

      gettext do
        backend AshGettextFixture.Gettext
        locale_resolver AshGettextFixture.ActorLanguage
        extract_messages_from #{inspect(folders)}
      end
    end
    """)
  end

  for {label, folder} <- [
        {"an absolute path", "/etc/app"},
        {"a path that climbs out", "lib/../../secrets"},
        {"the project root itself", "."}
      ] do
    test "refuses #{label}, naming the domain and the option" do
      name = "AshGettextFixture.Folders#{System.unique_integer([:positive])}"

      error = assert_raise Spark.Error.DslError, fn -> compile_domain(name, [unquote(folder)]) end

      assert Exception.message(error) =~ name
      assert Exception.message(error) =~ "extract_messages_from"
      assert Exception.message(error) =~ unquote(folder)
    end
  end

  test "accepts a relative folder that does not exist" do
    name = "AshGettextFixture.Folders#{System.unique_integer([:positive])}"

    assert [{_module, _binary}] = compile_domain(name, ["no/such/folder"])
  end
end
