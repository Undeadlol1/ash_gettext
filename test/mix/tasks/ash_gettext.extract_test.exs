defmodule Mix.Tasks.AshGettext.ExtractTest.OtherTemplate do
  @moduledoc """
  A second translating domain, naming a different `text_domain`.

  Two domains that disagree about where their template lives have no single
  answer for `--output`, and the task has to say so instead of guessing.
  """

  use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

  gettext do
    backend(AshGettextFixture.Gettext)
    text_domain("other")
  end

  resources do
  end
end

defmodule Mix.Tasks.AshGettext.ExtractTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.AshGettext.Extract

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    File.mkdir_p!(Path.join(dir, "lib"))

    File.write!(Path.join(dir, "lib/parcel.ex"), """
    defmodule Parcel do
      def validate(_), do: {:error, field: :weight, message: "is too heavy"}
    end
    """)

    %{src: Path.join(dir, "lib"), pot: Path.join(dir, "priv/gettext/ash_errors.pot")}
  end

  test "writes every Ash message into the template", %{src: src, pot: pot} do
    Extract.run([src, "--output", pot])

    assert File.read!(pot) =~ ~s(msgid "is too heavy")
  end

  test "--check passes on a current template and fails once a message is added",
       %{src: src, pot: pot} do
    Extract.run([src, "--output", pot])
    Extract.run([src, "--check", "--output", pot])

    File.write!(Path.join(src, "box.ex"), """
    defmodule Box do
      def validate(_), do: {:error, message: "is too wide"}
    end
    """)

    assert_raise Mix.Error, ~r/out of date/, fn ->
      Extract.run([src, "--check", "--output", pot])
    end
  end

  describe "choosing the template when no output is named" do
    setup do
      previous = Application.get_env(:ash_gettext, :ash_domains)
      on_exit(fn -> Application.put_env(:ash_gettext, :ash_domains, previous) end)

      # These tests run the task from a temporary directory, and Elixir's code
      # path holds relative entries, so a module not already loaded cannot be
      # found once the working directory changes. A real run never changes it.
      Enum.each(
        [
          AshGettextFixture.Shipping,
          AshGettextFixture.SwitchedOff,
          AshGettextFixture.Gettext
        ],
        &Code.ensure_loaded!/1
      )

      :ok
    end

    test "writes where the domain's own errors are looked up", %{tmp_dir: dir, src: src} do
      Application.put_env(:ash_gettext, :ash_domains, [
        AshGettextFixture.Shipping,
        AshGettextFixture.SwitchedOff
      ])

      File.cd!(dir, fn -> Extract.run([src]) end)

      assert File.read!(Path.join(dir, "priv/test_gettext/fixture.pot")) =~
               ~s(msgid "is too heavy")

      refute File.exists?(Path.join(dir, "priv/gettext/ash_errors.pot"))
    end

    test "asks which template when the domains disagree", %{tmp_dir: dir, src: src} do
      Application.put_env(:ash_gettext, :ash_domains, [
        AshGettextFixture.Shipping,
        Mix.Tasks.AshGettext.ExtractTest.OtherTemplate
      ])

      error =
        assert_raise Mix.Error, fn ->
          File.cd!(dir, fn -> Extract.run([src]) end)
        end

      assert error.message =~ "more than one template"
      assert error.message =~ "priv/test_gettext/fixture.pot"
      assert error.message =~ "priv/test_gettext/other.pot"
    end

    test "falls back to ash_errors.pot when no domain translates", %{tmp_dir: dir, src: src} do
      Application.put_env(:ash_gettext, :ash_domains, [AshGettextFixture.SwitchedOff])

      File.cd!(dir, fn -> Extract.run([src]) end)

      assert File.read!(Path.join(dir, "priv/gettext/ash_errors.pot")) =~
               ~s(msgid "is too heavy")
    end
  end
end
