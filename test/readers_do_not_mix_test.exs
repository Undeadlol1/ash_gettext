defmodule AshGettext.ReadersDoNotMixTest do
  @moduledoc """
  One app serves readers of different languages at once, and one process
  serves them one after another. Each must read their own language, whatever
  the reader before them was, on every way into Ash.
  """

  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AshGettextFixture.ApiRouter
  alias AshGettextFixture.Gettext, as: Backend
  alias AshGettextFixture.GraphSchema
  alias AshGettextFixture.Rules.Entry

  @russian %{language: "ru"}
  @english %{language: "en"}
  @nobody nil
  @too_light %{ru: "Вес должен быть не менее 30 кг", en: "Weight must be at least 30 kg"}
  @required %{ru: "обязательное поле", en: "is required"}
  @not_found %{ru: "не найдено", en: "No note record found with"}
  @ways [
    {:plain_ash, @too_light},
    {:phoenix_form, @too_light},
    {:json_api_rule, @too_light},
    {:json_api_body_check, @required},
    {:json_api_missing_record, @not_found},
    {:graphql, @too_light}
  ]
  @parsers Plug.Parsers.init(
             parsers: [:json, AshJsonApi.Plug.Parser],
             json_decoder: Jason,
             pass: ["*/*"]
           )

  defp too_light_entry,
    do: %{code: "code-#{System.unique_integer([:positive])}", quantity: 1, slug: "ab", weight: 5}

  defp language(@russian), do: :ru
  defp language(_english_or_nobody), do: :en

  defp json_detail(method, path, body, actor) do
    conn =
      conn(method, path, body && Jason.encode!(body))
      |> put_req_header("content-type", "application/vnd.api+json")
      |> put_req_header("accept", "application/vnd.api+json")
      |> Ash.PlugHelpers.set_actor(actor)
      |> Plug.Parsers.call(@parsers)
      |> ApiRouter.call(ApiRouter.init([]))

    [%{"detail" => detail}] = Jason.decode!(conn.resp_body)["errors"]
    detail
  end

  defp sentence(:plain_ash, actor) do
    {:error, %{errors: [error]}} = Ash.create(Entry, too_light_entry(), actor: actor)
    error.message
  end

  defp sentence(:phoenix_form, actor) do
    params = Map.new(too_light_entry(), fn {key, value} -> {to_string(key), to_string(value)} end)

    {:error, form} =
      Entry
      |> AshPhoenix.Form.for_create(:create, actor: actor)
      |> AshPhoenix.Form.submit(params: params)

    [{_field, sentence}] = AshPhoenix.Form.errors(form)
    sentence
  end

  defp sentence(:json_api_rule, actor),
    do:
      json_detail(
        :post,
        "/entries",
        %{data: %{type: "entry", attributes: too_light_entry()}},
        actor
      )

  defp sentence(:json_api_body_check, actor),
    do: json_detail(:post, "/notes", %{data: %{type: "note", attributes: %{}}}, actor)

  defp sentence(:json_api_missing_record, actor),
    do: json_detail(:get, "/notes/#{Ash.UUID.generate()}", nil, actor)

  defp sentence(:graphql, actor) do
    %{code: code, weight: weight, quantity: quantity, slug: slug} = too_light_entry()

    {:ok, %{data: %{"createEntry" => %{"errors" => [%{"message" => message}]}}}} =
      Absinthe.run(
        ~s|mutation { createEntry(input: {code: "#{code}", weight: #{weight}, quantity: #{quantity}, slug: "#{slug}"}) { errors { message } } }|,
        GraphSchema,
        context: %{actor: actor}
      )

    message
  end

  defp reads_own_language?(way, sentences, actor),
    do: sentence(way, actor) =~ Map.fetch!(sentences, language(actor))

  describe "one process serving readers one after another" do
    for {way, sentences} <- @ways do
      test "answers each in their own language through #{way}" do
        for actor <- [@russian, @english, @russian, @nobody, @russian, @russian, @english] do
          assert reads_own_language?(unquote(way), unquote(Macro.escape(sentences)), actor)
        end
      end

      test "is left with no reader and its own language after #{way}" do
        Gettext.put_locale(Backend, "en")

        sentence(unquote(way), @russian)

        assert Gettext.get_locale(Backend) == "en"
        assert AshGettext.JsonApi.request_actor() == nil
      end
    end
  end

  describe "many readers at the same moment" do
    test "each read their own language, on every way in" do
      readers = for number <- 1..60, do: Enum.at([@russian, @english, @nobody], rem(number, 3))

      mixed_up =
        readers
        |> Task.async_stream(
          fn actor ->
            for {way, sentences} <- @ways, not reads_own_language?(way, sentences, actor), do: way
          end,
          max_concurrency: 20,
          timeout: 30_000
        )
        |> Enum.flat_map(fn {:ok, ways} -> ways end)

      assert mixed_up == []
    end
  end

  describe "a reader whose request set Gettext's language to another one" do
    for {way, sentences} <- @ways do
      test "still reads their own language through #{way}" do
        Gettext.put_locale(Backend, "en")

        assert reads_own_language?(unquote(way), unquote(Macro.escape(sentences)), @russian)
      end
    end
  end
end
