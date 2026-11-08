defmodule AshGettext.EnumTest do
  use ExUnit.Case, async: true

  alias AshGettextFixture.Gettext, as: Backend
  alias AshGettextFixture.ParcelStatus

  defp in_ru(fun), do: Gettext.with_locale(Backend, "ru", fun)

  test "translates the default label" do
    assert in_ru(fn -> ParcelStatus.label(:placed) end) == "Заказ размещён"
  end

  test "translates a custom label" do
    assert in_ru(fn -> ParcelStatus.label(:shipped) end) == "В пути"
  end

  test "translates the description" do
    assert in_ru(fn -> ParcelStatus.description(:awaiting_pickup) end) ==
             "Готов к выдаче в пункте"
  end

  test "the source locale returns the source text" do
    Gettext.with_locale(Backend, "en", fn ->
      assert ParcelStatus.label(:shipped) == "On its way"
      assert ParcelStatus.description(:awaiting_pickup) == "Ready at the pickup point"
    end)
  end

  describe "labels are written" do
    test "a value without a label fails to compile and names it" do
      error =
        assert_raise CompileError, fn ->
          Code.compile_string("""
          defmodule AshGettextFixture.Unlabelled do
            use Ash.Type.Enum, values: [:a, b: [label: "Bee"], c: "only a description"]
            use AshGettext.Enum, backend: AshGettextFixture.Gettext
          end
          """)
        end

      assert error.description =~ ":a, :c"
      refute error.description =~ ":b"
    end
  end

  test "a value without a description stays nil" do
    assert in_ru(fn -> ParcelStatus.description(:placed) end) == nil
  end

  describe "a miss" do
    setup do
      id = {__MODULE__, make_ref()}
      test_pid = self()

      :telemetry.attach(
        id,
        [:ash_gettext, :translation, :missing],
        fn _event, _measurements, metadata, _ -> send(test_pid, {:missing, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
    end

    test "falls back to the source text and emits telemetry" do
      assert in_ru(fn -> ParcelStatus.label(:lost) end) == "Parcel lost"
      assert_receive {:missing, %{msgid: "Parcel lost", locale: "ru", text_domain: "fixture"}}
    end

    test "a hit emits nothing" do
      in_ru(fn -> ParcelStatus.label(:placed) end)
      refute_receive {:missing, %{msgid: "Order placed"}}
    end
  end

  describe "misuse" do
    test "requires :backend" do
      assert_raise ArgumentError, ~r/requires a :backend/, fn ->
        Code.compile_string("""
        defmodule AshGettext.EnumTest.NoBackend do
          use Ash.Type.Enum, values: [:a]
          use AshGettext.Enum
        end
        """)
      end
    end

    test "needs use Ash.Type.Enum first" do
      assert_raise CompileError, ~r/after use Ash.Type.Enum/, fn ->
        Code.compile_string("""
        defmodule AshGettext.EnumTest.NoEnum do
          use AshGettext.Enum, backend: AshGettextFixture.Gettext
        end
        """)
      end
    end
  end
end
