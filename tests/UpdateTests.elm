module UpdateTests exposing (..)

import Fuzz exposing (Fuzzer)
import Mouse exposing (Position)
import Test exposing (..)
import Expect as Should exposing (Expectation)
import Internal exposing (Drag(..), Msg(..))
import Draggable.Delta as Delta exposing (Delta)
import String


all : Test
all =
    describe "update"
        [ describe "single update" singleUpdateTests
        , describe "chain update" chainUpdateTests
        , describe
            "invalid updates leave the state unchanged"
            invalidUpdateTests
        ]


type EmitMsg
    = OnDragStart
    | OnDragBy Delta.Delta
    | OnDragEnd
    | OnClick


updateWithEvents : UpdateEmitter EmitMsg
updateWithEvents =
    Internal.updateAndEmit fullConfig


fullConfig : Internal.Config EmitMsg
fullConfig =
    { onDragStart = Just OnDragStart
    , onDragBy = Just << OnDragBy
    , onDragEnd = Just OnDragEnd
    , onClick = Just OnClick
    }


defaultUpdate : UpdateEmitter ()
defaultUpdate =
    Internal.updateAndEmit Internal.defaultConfig


singleUpdateTests : List Test
singleUpdateTests =
    [ fuzz positionF "NoDrag -[DragStart]-> DragAttempt (onDragStart)" <|
        \startPosition ->
            NoDrag
                |> updateWithEvents (DragStart startPosition)
                |> Should.equal ( TentativeDrag startPosition, [] )
    , fuzz2 positionF positionF "TentativeDrag -[DragAt]-> Dragging (onDragBy)" <|
        \p1 p2 ->
            TentativeDrag p1
                |> updateWithEvents (DragAt p2)
                |> Should.equal
                    ( Dragging p2
                    , [ OnDragStart, OnDragBy (Delta.distanceTo p2 p1) ]
                    )
    , fuzz2 positionF positionF "Dragging -[DragAt]-> Dragging (onDragBy)" <|
        \p1 p2 ->
            Dragging p1
                |> updateWithEvents (DragAt p2)
                |> Should.equal ( Dragging p2, [ OnDragBy (Delta.distanceTo p2 p1) ] )
    , fuzz positionF "TentativeDrag -[DragEnd]-> NoDrag (onClick)" <|
        \endPosition ->
            TentativeDrag endPosition
                |> updateWithEvents DragEnd
                |> Should.equal ( NoDrag, [ OnClick ] )
    , fuzz positionF "Dragging -[DragEnd]-> NoDrag (onDragEnd)" <|
        \endPosition ->
            Dragging endPosition
                |> updateWithEvents DragEnd
                |> Should.equal ( NoDrag, [ OnDragEnd ] )
    ]


invalidUpdateTests : List Test
invalidUpdateTests =
    [ fuzz positionF "Invalid DragAt from NoDrag" <|
        \position ->
            NoDrag
                |> updateWithEvents (DragAt position)
                |> Should.equal ( NoDrag, [] )
    , test "Invalid DragEnd from NoDrag" <|
        \() ->
            NoDrag
                |> updateWithEvents DragEnd
                |> Should.equal ( NoDrag, [] )
    , fuzz2 positionF positionF "Invalid DragStart from TentativeDrag" <|
        \position startPosition ->
            TentativeDrag position
                |> updateWithEvents (DragStart startPosition)
                |> Should.equal ( TentativeDrag position, [] )
    , fuzz2 positionF positionF "Invalid DragStart from Dragging" <|
        \position startPosition ->
            Dragging position
                |> updateWithEvents (DragStart startPosition)
                |> Should.equal ( Dragging position, [] )
    ]


chainUpdateTests : List Test
chainUpdateTests =
    [ fuzz2 positionF positionsStrictF "DragStart DragAt+ DragEnd" <|
        \startPosition dragPositions ->
            let
                msgs =
                    List.concat
                        [ [ DragStart startPosition ]
                        , List.map DragAt dragPositions
                        , [ DragEnd ]
                        ]

                expectedState =
                    NoDrag

                expectedEvents =
                    List.concat
                        [ [ OnDragStart ]
                        , List.map OnDragBy (deltas startPosition dragPositions)
                        , [ OnDragEnd ]
                        ]
            in
                NoDrag
                    |> chainUpdate updateWithEvents msgs
                    |> Should.equal ( expectedState, expectedEvents )
    , fuzz positionF "DragStart DragEnd" <|
        \startPosition ->
            let
                msgs =
                    [ DragStart startPosition, DragEnd ]

                expected =
                    ( NoDrag, [ OnClick ] )
            in
                NoDrag
                    |> chainUpdate updateWithEvents msgs
                    |> Should.equal expected
    , fuzz2 positionF positionF "no events if none configured" <|
        \startPosition endPosition ->
            let
                msgs =
                    [ DragStart startPosition
                    , DragAt endPosition
                    , DragEnd
                    , DragStart endPosition
                    , DragEnd
                    ]

                expected =
                    ( NoDrag, [] )
            in
                NoDrag
                    |> chainUpdate defaultUpdate msgs
                    |> Should.equal expected
    ]


deltas : Position -> List Position -> List Delta
deltas first rest =
    List.map2 Delta.distanceTo rest (first :: rest)



-- Fuzzers


positionsStrictF : Fuzzer (List Position)
positionsStrictF =
    Fuzz.map2 (::) positionF (Fuzz.list positionF)


positionF : Fuzzer Position
positionF =
    Fuzz.map2 Position Fuzz.int Fuzz.int



-- Update Helpers


type alias Emit msg model =
    ( model, List msg )


type alias UpdateEmitter msg =
    Msg -> Drag -> Emit msg Drag


chainUpdate : UpdateEmitter msg -> List Msg -> Drag -> Emit msg Drag
chainUpdate update msgs model =
    List.foldl (andThenEmit << update) ( model, [] ) msgs


andThenEmit : (a -> Emit msg a) -> Emit msg a -> Emit msg a
andThenEmit f ( model, msgs ) =
    let
        ( newModel, newMsgs ) =
            f model
    in
        ( newModel, msgs ++ newMsgs )