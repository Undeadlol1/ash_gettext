defmodule AshGettext.GraphqlTest do
  @moduledoc """
  AshGraphql writes the text of some errors itself ("is required", "could not
  be found"), after the domain's error handler is chosen. These run real
  documents through Absinthe and read the errors the client gets.
  """

  use ExUnit.Case, async: true

  alias AshGettextFixture.Gettext, as: Backend
  alias AshGettextFixture.Graph
  alias AshGettextFixture.GraphSchema

  @russian %{language: "ru"}
  @english %{language: "en"}

  defp run(document, actor), do: Absinthe.run(document, GraphSchema, context: %{actor: actor})

  defp create_note(fields, actor, mutation \\ "createNote") do
    {:ok, %{data: data}} =
      run(
        ~s|mutation { #{mutation}(input: {#{fields}}) { errors { message shortMessage code fields } } }|,
        actor
      )

    [error] = data[mutation]["errors"]
    error
  end

  defp create_own_note(fields, actor) do
    {:ok, %{data: data}} =
      run(
        ~s|mutation { createOwnNote(input: {#{fields}}) { errors { message code } } }|,
        actor
      )

    [error] = data["createOwnNote"]["errors"]
    error
  end

  defp fetch_note(id, actor) do
    {:ok, %{errors: [error]}} = run(~s|query { note(id: "#{id}") { id } }|, actor)
    error
  end

  describe "a Russian reader" do
    test "reads a missing required value as the Russian sentence" do
      assert %{"code" => "required", "message" => "обязательное поле", "fields" => ["title"]} =
               create_note(~s|weight: 40|, @russian)
    end

    test "reads a validation message with its values filled in" do
      assert %{"message" => "Вес должен быть не менее 30 кг", "fields" => ["weight"]} =
               create_note(~s|title: "t", weight: 5|, @russian)
    end

    test "reads an invalid attribute as the Russian sentence" do
      assert %{"code" => "invalid_attribute", "message" => "неверное значение"} =
               create_note(~s|title: "bad", weight: 40|, @russian)
    end

    test "reads a failed policy as the Russian sentence" do
      {:ok, %{data: data}} =
        run(
          "mutation { createVault { errors { message code } } }",
          @russian
        )

      assert [%{"code" => "forbidden", "message" => "Вам нельзя это делать"}] =
               data["createVault"]["errors"]
    end

    test "reads a record that is not there as the Russian sentence" do
      assert %{code: "not_found", message: "не найдено"} =
               fetch_note(Ash.UUID.generate(), @russian)
    end

    test "keeps the short message and the code a client may match on" do
      assert %{"code" => "required", "shortMessage" => "обязательное поле"} =
               create_note(~s|weight: 40|, @russian)
    end
  end

  describe "a reader in the source language" do
    test "gets the same reply as a domain with translation switched off" do
      assert create_note(~s|weight: 40|, @english) ==
               create_note(~s|weight: 40|, @english, "createStockNote")
    end

    test "reads a validation message with its values filled in, in English" do
      assert %{"message" => "Weight must be at least 30 kg"} =
               create_note(~s|title: "t", weight: 5|, @english)
    end
  end

  describe "the language comes from the actor, with no plug" do
    test "does not depend on Gettext's current language" do
      Gettext.put_locale(Backend, "en")

      assert %{"message" => "обязательное поле"} = create_note(~s|weight: 40|, @russian)
    end

    test "gives an actor whose language has no catalog the source language" do
      assert %{"message" => "is required"} = create_note(~s|weight: 40|, %{language: "de"})
    end

    test "gives a request with no actor the source language" do
      assert %{"message" => "is required"} = create_note(~s|weight: 40|, nil)
    end
  end

  describe "a domain with no error handler of its own" do
    test "gets the translating handler, wrapping AshGraphql's default one" do
      assert AshGraphql.Domain.Info.error_handler(Graph) ==
               {AshGettext.Graphql, :translate_error,
                [{AshGraphql.DefaultErrorHandler, :handle_error, []}]}
    end
  end

  describe "a domain that switched error translation off" do
    test "keeps AshGraphql's default handler" do
      assert AshGraphql.Domain.Info.error_handler(AshGettextFixture.StockGraph) ==
               {AshGraphql.DefaultErrorHandler, :handle_error, []}
    end

    test "replies in English even to a Russian reader" do
      assert %{"message" => "is required"} =
               create_note(~s|weight: 40|, @russian, "createStockNote")
    end
  end

  describe "an app with its own error handler" do
    test "has it run first, with its own arguments" do
      assert AshGraphql.Domain.Info.error_handler(AshGettextFixture.OwnGraph) ==
               {AshGettext.Graphql, :translate_error,
                [{AshGettextFixture.GraphOwnHandler, :handle_error, ["S-1"]}]}
    end

    test "keeps what it added, next to the translated sentence" do
      {:ok, %{data: data}} =
        run(
          ~s|mutation { createOwnNote(input: {weight: 40}) { errors { message code } } }|,
          @russian
        )

      assert [%{"message" => "обязательное поле"}] = data["createOwnNote"]["errors"]
    end

    test "still translates a validation message with its values" do
      assert %{"message" => "Вес должен быть не менее 30 кг"} =
               create_own_note(~s|title: "t", weight: 5|, @russian)
    end
  end

  describe "translate_error/2" do
    defp error(fields \\ []) do
      Map.merge(
        %{
          message: "is required",
          short_message: "is required",
          code: "required",
          vars: %{},
          fields: [:title]
        },
        Map.new(fields)
      )
    end

    defp context(actor), do: %{domain: Graph, actor: actor}

    test "changes message and short message and nothing else" do
      translated = AshGettext.Graphql.translate_error(error(), context(@russian))

      assert translated ==
               %{error() | message: "обязательное поле", short_message: "обязательное поле"}
    end

    test "uses the sentence the error carries in its vars" do
      carried = error(vars: [translation: "уже переведено"])

      assert %{message: "уже переведено"} =
               AshGettext.Graphql.translate_error(carried, context(@russian))
    end

    test "leaves an unknown code with an untranslated message alone" do
      unknown =
        error(
          code: "brand_new_in_the_next_ash",
          message: "a sentence Ash added later",
          short_message: "a sentence Ash added later"
        )

      assert AshGettext.Graphql.translate_error(unknown, context(@russian)) == unknown
    end

    test "leaves the error alone for a domain with no gettext block" do
      assert AshGettext.Graphql.translate_error(error(), %{
               domain: AshGettextFixture.Untranslated,
               actor: @russian
             }) == error()
    end

    test "leaves the error alone when the context names no domain" do
      assert AshGettext.Graphql.translate_error(error(), %{actor: @russian}) == error()
    end

    test "passes anything that is not an error map through" do
      assert AshGettext.Graphql.translate_error(:not_an_error, context(@russian)) ==
               :not_an_error

      assert AshGettext.Graphql.translate_error(%{message: "no short one"}, context(@russian)) ==
               %{message: "no short one"}
    end

    test "runs the app's own handler first, then translates what it returned" do
      own = {AshGettextFixture.GraphOwnHandler, :handle_error, ["S-9"]}

      assert %{message: "обязательное поле", support_code: "S-9"} =
               AshGettext.Graphql.translate_error(error(), context(@russian), own)
    end
  end

  describe "GraphQL's own schema validation" do
    test "is not ours to translate: Absinthe rejects the document before Ash runs" do
      {:ok, %{errors: [%{message: message}]}} =
        run(~s|mutation { createNote(input: {title: 5}) { errors { message } } }|, @russian)

      assert message =~ "Argument \"input\" has invalid value"
    end
  end
end
