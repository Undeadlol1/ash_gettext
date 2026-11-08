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
            use AshGettext.Enum,
              backend: AshGettextFixture.Gettext,
              values: [:a, b: [label: "Bee"], c: "only a description"]
          end
          """)
        end

      assert error.description =~ ":a, :c"
      refute error.description =~ ":b"
    end

    test "a written label that reads like the value's name is accepted" do
      modules =
        Code.compile_string("""
        defmodule AshGettextFixture.PlainlyLabelled do
          use AshGettext.Enum,
            backend: AshGettextFixture.Gettext,
            values: [placed: [label: "Placed"]]
        end
        """)

      {module, _binary} = List.keyfind(modules, AshGettextFixture.PlainlyLabelled, 0)
      assert module.label(:placed) == "Placed"
    end
  end

  test "an empty value has no label and no description" do
    assert ParcelStatus.label(nil) == nil
    assert ParcelStatus.description(nil) == nil
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
          use AshGettext.Enum, values: [a: [label: "A"]]
        end
        """)
      end
    end

    test "requires :values" do
      assert_raise ArgumentError, ~r/requires a :values/, fn ->
        Code.compile_string("""
        defmodule AshGettext.EnumTest.NoValues do
          use AshGettext.Enum, backend: AshGettextFixture.Gettext
        end
        """)
      end
    end
  end
end
