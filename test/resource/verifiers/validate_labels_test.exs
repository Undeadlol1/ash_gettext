defmodule AshGettext.Resource.Verifiers.ValidateLabelsTest do
  # Sync: the compiler reports on the global stderr.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defp compile(attribute) do
    capture_io(:stderr, fn ->
      Code.compile_string("""
      defmodule AshGettextFixture.Labelled#{System.unique_integer([:positive])} do
        use Ash.Resource, domain: nil, extensions: [AshGettext.Resource]

        attributes do
          uuid_primary_key :id
        end

        gettext do
          label #{inspect(attribute)}, "Written"
        end
      end
      """)
    end)
  end

  test "a label naming an attribute the resource lacks fails to compile" do
    assert compile(:nope) =~ "label :nope names an attribute this resource does not have"
  end

  test "a label naming a real attribute compiles clean" do
    refute compile(:id) =~ "names an attribute"
  end
end
