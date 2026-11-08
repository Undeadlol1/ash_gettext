defmodule AshGettext.Enum do
  @moduledoc """
  Make an `Ash.Type.Enum` return translated `label/1` and `description/1`.

      defmodule MyApp.Order.Status do
        use Ash.Type.Enum,
          values: [
            placed: [label: "Order placed"],
            awaiting_pickup: [label: "Ready for pickup", description: "Ready at the pickup point"]
          ]

        use AshGettext.Enum, backend: MyApp.Gettext
      end

      MyApp.Order.Status.label(:awaiting_pickup)
      #=> "Ожидает выдачи"

  Put it after `use Ash.Type.Enum`. The text you write is the msgid, so the
  source language needs no catalog.

  Every value needs a `label:` you wrote. The library never makes one from the
  value's name, so a value without one is a compile error. Descriptions are
  optional. A label equal to the value's name in sentence case (`"Placed"` for
  `:placed`) looks like Ash's own default and is rejected too; write what a
  person should read. The language is Gettext's current locale
  for the process (`Gettext.put_locale/2`, `Gettext.with_locale/3`). A missing
  translation returns the source text and emits the
  `[:ash_gettext, :translation, :missing]` telemetry event.

  ## Options

    * `:backend` - required; your Gettext backend.
    * `:text_domain` - the catalog the texts live in. Defaults to `"ash"`.
  """

  defmacro __using__(opts) do
    backend =
      Keyword.get(opts, :backend) ||
        raise ArgumentError, "use AshGettext.Enum requires a :backend option"

    text_domain = Keyword.get(opts, :text_domain, "ash")

    quote do
      unless Module.overridable?(__MODULE__, {:label, 1}) do
        raise CompileError,
          file: __ENV__.file,
          line: __ENV__.line,
          description: "use AshGettext.Enum must come after use Ash.Type.Enum"
      end

      AshGettext.Enum.verify_labels!(__MODULE__, __ENV__)

      @doc false
      def __ash_gettext_enum__, do: true

      def label(value),
        do: AshGettext.Enum.translate(unquote(backend), unquote(text_domain), super(value))

      def description(value),
        do: AshGettext.Enum.translate(unquote(backend), unquote(text_domain), super(value))
    end
  end

  @doc false
  # Ash fills a missing label with the value's name in sentence case. That
  # default is what we refuse, so a label equal to it counts as not written.
  def verify_labels!(module, env) do
    values_map = Module.get_attribute(module, :values_map)

    missing =
      for value <- Module.get_attribute(module, :values),
          values_map[value].label == ash_default_label(value),
          do: inspect(value)

    if missing != [] do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(module)} has values without a written label: #{Enum.join(missing, ", ")}. " <>
            "Give each one `label: \"...\"`; AshGettext never makes labels from value names."
    end
  end

  defp ash_default_label(value) do
    value |> to_string() |> String.replace(~r([^A-Za-z]), " ") |> String.capitalize()
  end

  @doc false
  def translate(backend, text_domain, text) when is_binary(text),
    do: AshGettext.translate(backend, text_domain, text, [], Gettext.get_locale(backend))

  def translate(_backend, _text_domain, other), do: other
end
