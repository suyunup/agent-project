import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import './style.css';

type Session = { id: number; input: string; output: string | null; phase: 'menu' | 'result' | 'sending'; message: string | null };
type Status = { permission: boolean; enabled: boolean };
const errorText = (error: unknown) => typeof error === 'string' ? error : '작업을 완료하지 못했습니다.';

function Main() {
  const [status, setStatus] = useState<Status>({ permission: false, enabled: false });
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let disposed = false;
    const refresh = () => invoke<Status>('status').then(value => { if (!disposed) setStatus(value); }).catch(error => { if (!disposed) setError(errorText(error)); });
    void refresh(); const timer = setInterval(refresh, 1000);
    return () => { disposed = true; clearInterval(timer); };
  }, []);
  async function run(command: string, args?: Record<string, unknown>) {
    setBusy(true); setError('');
    try { await invoke(command, args); setStatus(await invoke<Status>('status')); }
    catch (error) { setError(errorText(error)); }
    finally { setBusy(false); }
  }
  return <main className="main">
    <header><span className="eyebrow">CLIPWEAVE / M1</span><h1>복사한 텍스트를<br/>붙여넣기 전에 다듬기</h1><p className="muted">macOS 가공 붙여넣기 기술 검증</p></header>
    <section className="card"><div className="row"><div><h2>한 번만 가공하기</h2><p className="muted">평소 ⌘V는 그대로, 필요할 때 한 번만.</p></div><button aria-pressed={status.enabled} disabled={busy || !status.permission} onClick={() => run('set_enabled', { enabled: !status.enabled })}>{status.enabled ? '다음 ⌘V 대기 중 · 취소' : '다음 붙여넣기 한 번만 가공'}</button></div>
      <div className="permission"><span className={status.permission ? 'dot ok' : 'dot'}/>{status.permission ? '접근성 권한 허용됨' : '접근성 권한이 필요합니다'}<button className="secondary" disabled={busy} onClick={() => run('request_permission')}>권한 확인</button></div>
      {!status.permission && <p className="muted small">시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 ClipWeave를 허용한 뒤 다시 켜세요. 필요한 경우 앱을 다시 실행하세요.</p>}
    </section>
    <section><h2>이렇게 확인하세요</h2><ol><li>TextEdit 또는 Safari의 일반 입력창을 엽니다.</li><li><code>foo 한글 😀 foo</code>를 복사하고 ‘다음 붙여넣기 한 번만 가공’을 누릅니다.</li><li>대상 입력창에서 <kbd>⌘V</kbd>를 누릅니다.</li><li>테스트 치환을 선택하고 결과 확인 후 붙여넣습니다.</li></ol><p className="muted small">한 번 호출하면 자동 해제됩니다. · 치환: foo → bar<br/>복사/붙여넣기 후 클립보드에는 결과가 남습니다. 입력과 결과는 파일에 저장하지 않습니다. 1 MiB 초과 입력은 일반 붙여넣기로 통과합니다.</p></section>
    {error && <p role="alert" className="error">{error}</p>}
    <footer>TextEdit · Safari 우선 검증 / 이 창을 닫으면 앱이 종료됩니다.</footer>
  </main>;
}
function Overlay() {
  const [session, setSession] = useState<Session | null>(null);
  const [error, setError] = useState('');
  const [working, setWorking] = useState(false);
  const buttons = useRef<HTMLDivElement>(null);
  const cancelAction = useRef<() => void>(() => {});
  cancelAction.current = () => { void action('cancel'); };
  useEffect(() => {
    let disposed = false;
    let stop: (() => void) | undefined;
    void listen<number>('overlay-key', ({ payload: key }) => {
      if (disposed) return;
      if (key === 1) { cancelAction.current(); return; }
      const choices = [...(buttons.current?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)') ?? [])];
      if (!choices.length) return;
      const selected = choices.indexOf(document.activeElement as HTMLButtonElement);
      if (key === 4) { choices[Math.max(selected, 0)]?.click(); return; }
      const next = selected < 0 ? 0 : (selected + (key === 2 ? 1 : choices.length - 1)) % choices.length;
      choices[next]?.focus();
    }).then(unlisten => { if (disposed) unlisten(); else stop = unlisten; });
    return () => { disposed = true; stop?.(); };
  }, []);
  useEffect(() => {
    let disposed = false;
    let stop: (() => void) | undefined;
    let revision = 0;
    void listen<Session | null>('session', event => { revision++; if (!disposed) { setSession(event.payload); setError(''); } }).then(async unlisten => {
      if (disposed) { unlisten(); return; } stop = unlisten;
      const before = revision;
      const value = await invoke<Session | null>('current_session');
      if (!disposed && before === revision) setSession(value);
    }).catch(error => { if (!disposed) setError(errorText(error)); });
    return () => { disposed = true; stop?.(); };
  }, []);
  useEffect(() => { buttons.current?.querySelector<HTMLButtonElement>('button')?.focus(); setError(''); }, [session?.id, session?.phase]);
  async function action(action: string) {
    if (!session || working) return;
    setWorking(true); setError('');
    try { await invoke('session_action', { id: session.id, action }); }
    catch (error) { setError(errorText(error)); }
    finally { setWorking(false); }
  }
  return <main className="overlay" onKeyDown={event => {
    if (event.key === 'Escape') { event.preventDefault(); void action('cancel'); }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault(); const choices = [...(buttons.current?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)') ?? [])];
      const index = choices.indexOf(document.activeElement as HTMLButtonElement);
      choices[(index + (event.key === 'ArrowDown' ? 1 : choices.length - 1)) % choices.length]?.focus();
    }
  }}>
    <header><span className="eyebrow">CLIPWEAVE</span><h1>{session?.phase === 'menu' ? '어떻게 붙여넣을까요?' : '변환 결과 확인'}</h1></header>
    {!session ? <p className="muted">호출을 기다리고 있습니다.</p> : <>
      {session.phase === 'menu' ? <><p className="muted">테스트 치환 · foo → bar</p><label>원문</label><pre>{session.input}</pre></> : <div className="previews"><label>원문</label><pre>{session.input}</pre><label>결과</label><pre>{session.output}</pre></div>}
      <div className="actions" ref={buttons}>
        {session.phase === 'menu' ? <><button disabled={working} onClick={() => action('transform')}>테스트 치환</button><button className="secondary" disabled={working} onClick={() => action('pasteOriginal')}>원문 붙여넣기</button></> : <><button disabled={working || session.phase === 'sending'} onClick={() => action('pasteResult')}>붙여넣기</button><button className="secondary" disabled={working || session.phase === 'sending'} onClick={() => action('copy')}>결과 복사</button></>}
        <button className="secondary" disabled={working} onClick={() => action('cancel')}>취소 <span>Esc</span></button>
      </div>
      {(error || session.message) && <p role="status" className={error ? 'error' : 'notice'}>{error || session.message}</p>}
      <p className="muted small">↑ ↓ 선택 · Enter 실행 · Esc 취소</p>
    </>}
  </main>;
}
createRoot(document.getElementById('root')!).render(window.location.search.includes('overlay') ? <Overlay/> : <Main/>);
