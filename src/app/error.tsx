"use client";
import { useEffect } from "react";
export default function GlobalError({error,reset}:{error:Error & {digest?:string};reset:()=>void}){
 useEffect(()=>{console.error("STO.Flow runtime error:",error)},[error]);
 return <main className="auth-page"><section className="auth-card"><div className="auth-brand">STO.Flow<small>WORKSHOP OPERATIONS · 6.0</small></div><h1>Не удалось открыть раздел</h1><p className="subtitle">Произошла ошибка при загрузке данных или выполнении операции. Данные не следует вводить повторно, пока не проверено, сохранилась ли предыдущая операция.</p><div className="error">{error.message||"Неизвестная ошибка."}{error.digest?<div className="cell-sub">Код обращения: {error.digest}</div>:null}</div><button className="btn" onClick={()=>reset()}>Повторить загрузку</button><a className="btn outline" href="/today" style={{marginTop:8}}>На главную</a></section></main>
}
