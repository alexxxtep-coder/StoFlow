import { signIn } from "./actions";
export default async function LoginPage({searchParams}:{searchParams:Promise<{error?:string}>}) {
  const params=await searchParams;
  return <main className="auth-page"><section className="auth-card"><div className="auth-brand">STO.Flow<small>WORKSHOP OPERATIONS · 6.0</small></div><h1>Вход в систему</h1><p className="subtitle">Используйте учётную запись вашего автосервиса.</p>{params.error?<div className="error">Не удалось войти. Проверьте email и пароль.</div>:null}<form action={signIn}><label className="field">Email<input name="email" type="email" required autoComplete="email"/></label><label className="field">Пароль<input name="password" type="password" required autoComplete="current-password"/></label><button className="btn">Войти в STO.Flow</button></form><p className="cell-sub" style={{marginTop:17}}>Управление учётными записями и приглашение сотрудников выполняются администратором через Supabase Auth.</p></section></main>;
}
