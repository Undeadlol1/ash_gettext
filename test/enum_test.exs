defmodule AshGettext.EnumTest do
  use ExUnit.Case, async: true

  alias AshGettextFixture.CrateSize
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

  test "an enum where no value has a description gives nil" do
    assert in_ru(fn -> CrateSize.description(:small) end) == nil
    assert CrateSize.description(:large) == nil
  end

  test "an unknown value fails the same way Ash's own enum does" do
    # apply/3, so the compiler does not reject the unknown value up front.
    assert_raise FunctionClauseError, fn -> apply(ParcelStatus, :label, [:unknown]) end
    assert_raise FunctionClauseError, fn -> apply(ParcelStatus, :description, [:unknown]) end
  end

  describe "a miss" do
    setup do
      id = {__MODULE__, make_ref()}
      test_pid = self()

      :telemetry.attach(
        id,
        [:ash_gettext, :translation, :missing],
        fn _event, _measurements, metadata, _ ->
          if self() == test_pid, do: send(test_pid, {:missing, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
    end

    test "falls back to the source text and emits telemetry" do
      assert in_ru(fn -> ParcelStatus.label(:lost) end) == "Parcel lost"
      assert_receive {:missing, %{msgid: "Parcel lost", locale: "ru", text_domain: "fixture"}}
    end

    test "a description with no translation falls back to the source text and emits telemetry" do
      assert in_ru(fn -> ParcelStatus.description(:lost) end) == "Nobody knows where it is"
      assert_receive {:missing, %{msgid: "Nobody knows where it is", locale: "ru"}}
    end

    test "a hit emits nothing" do
      in_ru(fn -> ParcelStatus.label(:placed) end)
      in_ru(fn -> ParcelStatus.description(:awaiting_pickup) end)
      refute_receive {:missing, _}
    end

    test "a value without a description gives nil in any language and emits nothing" do
      assert in_ru(fn -> ParcelStatus.description(:placed) end) == nil

      assert Gettext.with_locale(Backend, "en", fn -> ParcelStatus.description(:placed) end) ==
               nil

      refute_receive {:missing, _}
    end

    test "the source language emits nothing" do
      Gettext.with_locale(Backend, "en", fn ->
        assert ParcelStatus.label(:lost) == "Parcel lost"
        assert ParcelStatus.description(:lost) == "Nobody knows where it is"
      end)

      refute_receive {:missing, _}
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
