defmodule AshGettext.Domain.Verifiers.ResourcesOptInTest do
  @moduledoc """
  The check is opt-in: a domain that does not ask for it must keep compiling
  with resources that never joined the extension.

  Fixtures are compiled from strings under unique module names so each case
  gets its own domain and nothing collides across runs.
  """

  use ExUnit.Case, async: true

  defp compile_domain(verify?, resource_extensions) do
    id = System.unique_integer([:positive])
    resource = "AshGettextFixture.OptIn#{id}.Resource"
    domain = "AshGettextFixture.OptIn#{id}.Domain"

    Code.compile_string("""
    defmodule #{resource} do
      use Ash.Resource,
        domain: #{domain},
        data_layer: Ash.DataLayer.Simple,
        extensions: #{inspect(resource_extensions)}

      attributes do
        uuid_primary_key :id
      end
    end

    defmodule #{domain} do
      use Ash.Domain, extensions: [AshGettext.Domain], validate_config_inclusion?: false

      gettext do
        backend AshGettextFixture.Gettext
        verify_resources? #{verify?}
      end

      resources do
        resource #{resource}
      end
    end
    """)

    resource
  end

  # Spark runs verifiers in an after-compile hook and reports their errors on
  # stderr instead of raising, and its `Spark.Test` collector does not reach the
  # process that hook runs in, so the failure is observed on stderr.
  import ExUnit.CaptureIO

  defp stderr_of(verify?, extensions) do
    capture_io(:stderr, fn -> compile_domain(verify?, extensions) end)
  end

  test "off, a resource without the extension compiles" do
    refute stderr_of(false, []) =~ "AshGettext.Resource"
  end

  test "on, every resource opted in compiles" do
    refute stderr_of(true, [AshGettext.Resource]) =~ "AshGettext.Resource"
  end

  test "on, a resource lacking the extension fails compilation and is named" do
    output = stderr_of(true, [])

    assert output =~ "Spark.Error.DslError"
    assert output =~ ~r/\* AshGettextFixture\.OptIn\d+\.Resource/
    assert output =~ "Add AshGettext.Resource"
  end
end
