import Lean.Elab

import WidgetKit.Svg

open Lean.Widget.Jsx
open Lean Widget


private def Float.toInt (x : Float) : Int :=
  if x >= 0 then
    x.toUInt64.toNat
  else
    -((-x).toUInt64.toNat)

namespace Svg

inductive ActionKind where
  | timeout
  | mousedown
  | mouseup
  | mousemove -- [note] mouse moves only happen when mouse button is down.
  deriving ToJson, FromJson, DecidableEq

structure Action where
  kind : ActionKind
  id : Option String
  data : Option Json
  deriving ToJson, FromJson

/-- The input type `State` is any state the user wants to use and update 

SvgState in addition automatically handles tracking of time, selection and custom data -/
structure SvgState (State : Type) where
  state : State
  time : Float /-- time in milliseconds -/
  selected : Option String
  mousePos : Option (Int × Int)
  idToData : List (String × Json)
deriving ToJson, FromJson

structure UpdateParams (State : Type) where
  elapsed : Float
  actions : Array Action
  state : SvgState State
  mousePos : Option (Float × Float) -- TODO: change to Option (Int × Int) or do we want to support subpixel precision?
  deriving ToJson, FromJson

structure UpdateResult (State : Type) where
  html : Widget.Html
  state : SvgState State
  /-- Approximate number of milliseconds to wait before calling again. -/
  callbackTime : Option Float := some 33
  deriving ToJson, FromJson

-- maybe add title, refresh rate, initial time?, custom selection rendering
structure InteractiveSvg (State : Type) where
  init : State
  frame : Svg.Frame
  update (time_ms Δt_ms : Float) (action : Action) 
         (mouseStart mouseEnd : Option (Svg.Point frame)) 
         (selectedId : Option String) (getSelectedData : (α : Type) → [FromJson α] → Option α)
         : State → State
  render (mouseStart mouseEnd : Option (Svg.Point frame)) : State → Svg frame

open Server RequestM in
def InteractiveSvg.serverRpcMethod {State : Type} (isvg : InteractiveSvg State) (params : UpdateParams State) 
  : RequestM (RequestTask (UpdateResult State)) := do

  -- Ideally, each action should have time and mouse position attached
  -- right now we just assume that all actions are uqually spaced within the frame
  let Δt := (params.elapsed - params.state.time) / params.actions.size.toFloat

  let idToData : HashMap String Json := HashMap.ofList params.state.idToData

  let mut time := params.state.time
  let mut state := params.state.state
  let mut selected := params.state.selected

  let getData := λ (α : Type) [FromJson α] => do 
    let id ← selected; 
    let data ← idToData[id]
    match fromJson? (α:=α) data with
    | .error _ => none
    | .ok val => some val

  
  let mouseStart := params.state.mousePos.map λ (i,j) => (i, j)
  let mouseEnd := params.mousePos.map λ (x,y) => (x.toInt, y.toInt)

  for action in params.actions do
    -- todo: interpolate mouse movenment!

    -- update state
    state := isvg.update time Δt action mouseStart mouseEnd selected getData state

    -- update selection
    if action.kind == ActionKind.mousedown then
      selected := action.id
    if action.kind == ActionKind.mouseup then
      selected := none

    -- update time
    time := time + Δt

  let mut svg := isvg.render mouseStart mouseEnd state
  
  let svgState : SvgState State := 
    { state := state 
      time := params.elapsed
      selected := selected
      mousePos := mouseEnd.map λ p => p.toPixels
      idToData := svg.idToDataList }


  -- highlight selection
  if let some id := selected then
    if let some idx := svg.idToIdx[id] then
      svg := { elements := svg.elements.modify idx λ e => e.setStroke (1.,1.,0.) (.px 5) }


  return RequestTask.pure {
    html := <div>
      <div>
        {svg.toHtml}
      </div>

      {toString params.elapsed}
      {toString <| toJson <| params.actions}
      {toString <| toJson <| mouseStart}
      {toString <| toJson <| mouseEnd}
      {toString <| toJson <| selected}</div>,
    state := svgState,
    callbackTime := some 33,
  }

end Svg
 
open Svg

abbrev State := Array (Float × Float)

def isvg : InteractiveSvg State where
  init := #[(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
  frame := 
    { xmin := -1
      ymin := -1
      xSize := 2
      width := 400
      height := 400 }
  update time Δt action mouseStart mouseEnd selected getData state :=
    match getData Nat, mouseEnd with 
    | some id, some p => state.set! id p.toAbsolute
    | _, _ => state

    -- state.map λ (x,y) => (x + Δt/10000 * Float.sin (time/1000), y)
  render mouseStart mouseEnd state := 
    { 
      elements := 
        let mousePointer := 
          match mouseStart, mouseEnd with
          | some s, some e => 
            #[ 
              Svg.circle e (.px 5) |>.setFill (1.,1.,1.),
              Svg.line s e |>.setStroke (1.,1.,1.) (.px 2)
            ]
          | _, _ => #[]
        let circles := (state.mapIdx fun idx (p : Float × Float) => 
              Svg.circle p (.abs 0.2) |>.setFill (0.7,0.7,0.7) |>.setId s!"circle{idx}" |>.setData idx.1
            )
        mousePointer.append circles
    }


open Server RequestM in
@[server_rpc_method]
def updateSvg (params : UpdateParams State) : RequestM (RequestTask (UpdateResult State)) := isvg.serverRpcMethod params

@[widget]
def svgWidget : UserWidgetDefinition where
  name := "Interactive SVG"
  javascript := include_str ".." / "widget" / "dist" / "interactiveSvg.js"


def init : UpdateResult State := {
  html := <div>Init!!!</div>,
  state := { state := isvg.init
             time := 0
             selected := none
             mousePos := none
             idToData := isvg.render none none isvg.init |>.idToDataList}
}

#widget svgWidget (toJson init)