import * as React from 'react'
import { useAsync, RpcContext, RpcSessionAtPos, RpcPtr, Name, DocumentPosition, mapRpcError }
  from '@leanprover/infoview'
import HtmlDisplay, { Html } from './htmlDisplay'
import InteractiveExpr from './interactiveExpr'

type ExprWithCtx = RpcPtr<'WidgetKit.ExprWithCtx'>

interface PresenterId {
  name: Name
  userName: string
}

async function applicableExprPresenters(rs: RpcSessionAtPos, expr: ExprWithCtx):
    Promise<PresenterId[]> {
  const ret: any = await rs.call('WidgetKit.applicableExprPresenters', { expr })
  return ret.presenters
}

async function getExprPresentation(rs: RpcSessionAtPos, expr: ExprWithCtx, name: Name):
    Promise<Html> {
  return await rs.call('WidgetKit.getExprPresentation', { expr, name })
}

interface ExprPresentationUsingProps {
  pos: DocumentPosition
  expr: ExprWithCtx
  name: Name
}

// TODO: a UseAsync component which displays the resolved/loading/error like we always do

function ExprPresentationUsing({pos, expr, name}: ExprPresentationUsingProps): JSX.Element {
  const rs = React.useContext(RpcContext)
  const st = useAsync(() => getExprPresentation(rs, expr, name), [rs, expr, name])
  return st.state === 'resolved' ? <HtmlDisplay pos={pos} html={st.value} />
    : st.state === 'loading' ? <>Loading..</>
    : <>Error: {mapRpcError(st.error).message}</>
}

export default function({pos, expr}: {pos: DocumentPosition, expr: ExprWithCtx}): JSX.Element {
  const rs = React.useContext(RpcContext)
  const st = useAsync(() => applicableExprPresenters(rs, expr), [rs, expr])
  const [selection, setSelection] = React.useState<Name | undefined>(undefined)

  if (st.state === 'rejected')
    return <>Error: {mapRpcError(st.error).message}</>
  else if (st.state === 'resolved' && 0 < st.value.length)
    return <>
        {selection && selection !== 'none' ?
          <ExprPresentationUsing pos={pos} expr={expr} name={selection} /> :
          <InteractiveExpr expr={expr} />}
        <select className='fr' onChange={ev => setSelection(ev.target.value)}>
          <option key='none' value='none'>Default</option>
          {st.value.map(pid => <option key={pid.name} value={pid.name}>{pid.userName}</option>)}
        </select>
      </>
  else
    return <InteractiveExpr expr={expr} />
}