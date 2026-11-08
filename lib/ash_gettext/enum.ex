defmodule AshGettext.Enum do
  @moduledoc """
  An `Ash.Type.Enum` whose `label/1` and `description/1` come back translated.

      defmodule MyApp.Order.Status do
        use AshGettext.Enum,
          backend: MyApp.Gettext,
          values: [
            placed: [label: "Order placed"],
            awaiting_pickup: [label: "Ready for pickup", description: "Ready at the pickup point"]
          ]
      end

      MyApp.Order.Status.label(:awaiting_pickup)
      #=> "Ожидает выдачи"

  It calls `use Ash.Type.Enum` for you with the same `values:`, so the module
  is an ordinary Ash enum. The text you write is the msgid, so the source
  language needs no catalog, and `mix gettext.extract` finds every label and
  description.

  Every value needs a `label:` you wrote. The library never makes one from the
  value's name, so a value without one is a compile error. Descriptions are
  optional. An empty value (`nil`) has no label and no description. The
  language is Gettext's current locale for the process; choose it with
  `Gettext.with_locale/3`. A loaded `<attribute>_label` uses the actor's
  language instead. A missing translation
  returns the source text and emits the `[:ash_gettext, :translation, :missing]`
  telemetry event.

  ## Options

    * `:backend` - required; your Gettext backend.
    * `:values` - required; the values, as for `Ash.Type.Enum`, each with a
      `label:`.
    * `:text_domain` - the catalog the texts live in. Defaults to `"ash"`.
  """

  defmacro __using__(opts) do
    backend =
      Keyword.get(opts, :backend) ||
        raise ArgumentError, "use AshGettext.Enum requires a :backend option"

    values =
      Keyword.get(opts, :values) ||
        raise ArgumentError, "use AshGettext.Enum requires a :values option"

    text_domain = Keyword.get(opts, :text_domain, "ash")

    quote do
      AshGettext.Enum.verify_labels!(__MODULE__, unquote(values), __ENV__)

      AshGettext.Extractor.mark(
        __ENV__,
        unquote(backend),
        unquote(text_domain),
        AshGettext.Enum.texts(unquote(values))
      )

      use Ash.Type.Enum, values: unquote(values)

      @doc false
      def __ash_gettext_enum__, do: true

      def label(nil), do: nil

      def label(value),
        do: AshGettext.Enum.translate(unquote(backend), unquote(text_domain), super(value))

      def description(nil), do: nil

      def description(value),
        do: AshGettext.Enum.translate(unquote(backend), unquote(text_domain), super(value))
    end
  end

  @doc false
  # Checks the values as written, before Ash fills in labels of its own.
  def verify_labels!(module, values, env) do
    missing =
      for entry <- values, not written_label?(entry), do: inspect(value_of(entry))

    if missing != [] do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(module)} has values without a written label: #{Enum.join(missing, ", ")}. " <>
            "Give each one `label: \"...\"`; AshGettext never makes labels from value names."
    end
  end

  @doc false
  # The labels and descriptions as written, for `mix gettext.extract`.
  def texts(values) do
    for {_value, details} when is_list(details) <- values,
        text <- [details[:label], details[:description]],
        is_binary(text),
        do: text
  end

  defp written_label?({_value, details}) when is_list(details),
    do: is_binary(Keyword.get(details, :label))

  defp written_label?(_entry), do: false

  defp value_of({value, _details}), do: value
  defp value_of(value), do: value

  @doc false
  def translate(backend, text_domain, text) when is_binary(text),
    do: AshGettext.translate(backend, text_domain, text, [], Gettext.get_locale(backend))

  def translate(_backend, _text_domain, other), do: other
end
