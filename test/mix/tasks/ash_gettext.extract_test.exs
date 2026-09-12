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
end
