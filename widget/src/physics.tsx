import {Html, StaticHtml, Elt} from './staticHtml';
import * as React from 'react';
import { RpcContext, mapRpcError } from '@leanprover/infoview';

type State = any

type Action =
  ( {kind : 'timeout'}
  | {kind : 'click', value : any}
  )

interface UpdateParams {
    /** Number of milliseconds of elapsed time since component was created. */
    elapsed : number;
    actions : Action[];
    state : State;
}

interface UpdateResult {
    html : Html;
    state : State
    callbackTime? : number
}

export function Physics(props : UpdateResult) {
    const rs = React.useContext(RpcContext)
    const [state, setState] = React.useState<UpdateResult>(props)
    const frameNo = React.useRef(0)
    const startTime = React.useRef(new Date())
    const pending = React.useRef<Action[]>([])
    const asyncState = React.useRef('init')

    React.useEffect(() => {
        if (state.callbackTime) {
            const t = setTimeout(() => increment({kind : 'timeout'}), state.callbackTime)
            return () => clearTimeout(t)
        }
    }, [state.callbackTime, frameNo.current])

    function increment(action : Action) {
        pending.current.push(action)
        dispatch()
    }
    async function dispatch() {
        if (asyncState.current === "loading") {
            return
        }
        const actions = pending.current
        pending.current = []
        asyncState.current = 'loading'
        const elapsed = (new Date() as any) - (startTime.current as any)
        const result = await rs.call<UpdateParams, UpdateResult>(
            'updatePhysics',
            { elapsed, actions, state : state.state })
        asyncState.current = 'resolved'
        frameNo.current = (frameNo.current + 1)
        setState(result)
        if (pending.current.length > 0) {
            dispatch()
        }
    }

    function visitor(e : Elt) : Elt {
        if ('click' in e.attrs) {
            let {click, ...attrs} = e.attrs
            attrs.onClick = () => increment({'kind' : 'click', 'value' : click})
            return {...e, attrs}
        }
        return e
    }

    return <div>
        <StaticHtml html={state.html} visitor={visitor}/>
        <div>frame: {frameNo.current}. state: {asyncState.current}</div>
    </div>
}

export default Physics