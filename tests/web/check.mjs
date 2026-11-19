// Web 版をまとめて確かめる(Chrome 1 回の起動で済ませる): 起動の時間・届くキー(R-2)・S0→S1→S2→S3→もう1回(AC-18)・
// 一時停止(タブが裏に回る)・保存と ParryDuel の保存の共存(AC-21)・読み込み後の通信 0 件(NFR-8)・打ってから描くまで(NFR-2)。
// 研修の夜を本当の時間で 1 回通すので 5 分ほどかかる。
//     node tests/web/check.mjs            手元の build/web を配って確かめる
//     RC_URL=https://…/root-call/ node tests/web/check.mjs   公開した物を確かめる
import { expect, failureCount, open, serve, sleep } from './lib.mjs';

const site = serve();
const page = await open(site.url + '?debug=1');
try {
	expect(page.booted, `起動した(${page.bootMs} ms)`);
	const s0 = await page.waitState((s) => s.screen === 'gate', 30000);
	expect(!!s0, 'S0 が出る');
	const loadedAt = Date.now();
	await page.evaluate(`localStorage.setItem('parry-duel/save', '{"version":1,"keep":"me"}')`);
	console.log(`    S0 が出るまで: ${Date.now() - page.t0} ms(ページを開いてから)`);
	await page.shot('s0');
	await page.touch(...(await page.gameCss(640, 360)));
	await sleep(800);
	const g = await page.state();
	expect(g.screen === 'gate', `タッチでは始まらない(FR-29): ${g.screen}`);
	await page.key('x');
	expect(!!(await page.waitState((s) => s.screen === 'title')), 'キーで S1');
	await sleep(300);
	await page.shot('s1_title');
	await page.key('Enter');
	const p0 = await page.waitState((s) => s.screen === 'play');
	expect(!!p0, 'Enter で研修の夜(一番上)');
	const line = async () => (await page.state()).play?.line;

	// R-2: Tab・→・BackSpace がゲームに届き、ページが動かないか
	const href = await page.evaluate('location.href');
	await page.type('ss');
	await page.key('Tab');
	await sleep(150);
	expect((await line()) === 'ssh ', `Tab で補完: "${await line()}"`);
	expect((await page.evaluate('document.activeElement && document.activeElement.id')) === 'canvas', 'Tab でフォーカスが動かない');
	await page.type('w');
	await page.key('ArrowRight');
	await sleep(150);
	expect((await line()) === 'ssh web0', `行末の → で補完: "${await line()}"`);
	await page.type('1\n');
	expect(!!(await page.waitState((s) => s.play?.loc === 0, 3000)), 'ssh web01 が効く');
	await page.type('abc');
	await page.key('Backspace');
	await sleep(150);
	expect((await line()) === 'ab', `BackSpace で消える: "${await line()}"`);
	expect((await page.evaluate('location.href')) === href, 'BackSpace でページが戻らない');
	await page.key('Backspace');
	await page.key('Backspace');
	await page.type('=_S/');
	await sleep(150);
	expect((await line()) === '=_s/', `記号と Shift の文字: "${await line()}"`);
	const keys = (await page.state()).keys.slice(-4).map((k) => `${k.pk_name}:${k.unicode}${k.shift ? '+shift' : ''}`);
	console.log('    届いたキー: ' + keys.join(' / '));
	for (let i = 0; i < 4; i++) await page.key('Backspace');
	await page.key('ArrowUp');
	await sleep(150);
	expect((await line()) === 'ssh web01', `↑ で履歴: "${await line()}"`);
	await page.key('ArrowDown');
	await sleep(150);
	expect((await line()) === '', '↓ で戻る');

	// web01 の停止(0:05)を直す
	await page.waitState((s) => s.play?.incidents >= 1, 10000);
	await page.type('sudo systemctl restart nginx\n');
	expect(!!(await page.waitState((s) => s.play?.fixed >= 1, 5000)), '研修の 1 件目が直る');

	// 打ってから描くまで(a と BackSpace を 50 回ずつ)
	for (let i = 0; i < 50; i++) {
		await page.key('a');
		await sleep(70);
		await page.key('Backspace');
		await sleep(70);
	}
	await sleep(1500);
	console.log('    打ってから描くまで・1 フレーム(ms): ' + JSON.stringify(await page.stats()));

	// 2 件目(db01)の画面を撮る
	await page.waitState((s) => s.play?.tick >= 37 * 120, 40000);
	await page.shot('s2_play_db01');
	await page.type('ssh db01\n', 30);
	await page.waitState((s) => s.play?.loc === 3, 3000);
	// やさしい(既定): 空の行の Tab で直すコマンドが入る
	await page.key('Tab');
	await sleep(150);
	expect((await line()) === 'restart', `やさしい: 空の行の Tab で直す形: "${await line()}"`);
	await page.shot('s2_play_cause');
	await page.key('Enter');
	expect(!!(await page.waitState((s) => s.play?.fixed >= 2, 6000)), 'db01 を直すと 2 件目が直る');
	await sleep(250);
	await page.shot('s2_play_ripple');

	// タブが裏に回ると一時停止(E-13)。戻っても自動では再開しない
	await page.hide();
	await sleep(1000);
	await page.show();  // 裏の間は描かないので、状態の窓口は戻ってから読む
	expect(!!(await page.waitState((s) => s.paused, 5000)), 'タブが裏で一時停止');
	await sleep(500);
	const t1 = (await page.state()).play.tick;
	await sleep(1000);
	expect((await page.state()).play.tick === t1, '戻っても止まったまま');
	await page.shot('s5_pause');
	await page.key('Escape');
	expect(!!(await page.waitState((s) => !s.paused, 3000)), 'Esc で続ける');

	// 夜が明けるまで待つ
	const res = await page.waitState((s) => s.screen === 'result', 260000);
	expect(!!res, '夜が明けて S3');
	await sleep(800);
	await page.shot('s3_result');
	const saved = await page.saved();
	expect(saved?.training_done === true, `保存が root-call/save に入る: ${JSON.stringify(saved)}`);
	expect((await page.evaluate(`localStorage.getItem('parry-duel/save')`)) === '{"version":1,"keep":"me"}', 'ParryDuel の保存を消さない');
	// コピー(FR-22): ボタンと、枠を選んで Ctrl+C
	await page.evaluate(`navigator.clipboard.writeText('').catch(() => {})`);
	await page.clickButton('copy');
	await sleep(500);
	const c1 = await page.clipboard();
	expect(c1.startsWith('RootCall '), `コピーのボタン: ${JSON.stringify(c1).slice(0, 80)}`);
	await page.evaluate(`navigator.clipboard.writeText('').catch(() => {})`);
	await page.click(...(await page.gameCss(500, 500)));  // 共有の枠(y 462〜554)
	await sleep(200);
	await page.keyMod('a', 2);
	await page.keyMod('c', 2);
	await sleep(500);
	const c2 = await page.clipboard();
	expect(c2.startsWith('RootCall '), `枠を選んで Ctrl+C: ${JSON.stringify(c2).slice(0, 80)}`);
	expect((await page.state()).screen === 'result', 'Ctrl 付きのキーでは画面が変わらない');
	await page.key('Escape');
	await sleep(400);
	await page.key('r');
	expect(!!(await page.waitState((s) => s.screen === 'play', 3000)), 'もう1回(R)');

	const after = page.requests.filter((r) => r.at > loadedAt);
	expect(after.length === 0, `読み込みの後の通信 ${after.length} 件(${Math.round((Date.now() - loadedAt) / 1000)} 秒見た)` + (after.length ? ': ' + after.map((r) => r.url).join(', ') : ''));
	console.log('    転送した大きさ: ' + JSON.stringify(page.sizes()));
	// キーの確かめの画面(?keys=1)
	const base = page.url0.split('?')[0];
	expect(await page.goto(base + '?keys=1&debug=1'), 'キーの確かめの画面を開き直す');
	await page.waitState((s) => s.screen === 'gate', 20000);
	await page.key('x');
	expect(!!(await page.waitState((s) => s.screen === 'keys', 3000)), '?keys=1 でキーの確かめの画面');
	await page.type('a=_/', 80);
	await page.key('Tab');
	await sleep(300);
	await page.shot('keys');
	const kl = (await page.state()).keys.slice(-5).map((k) => `${k.pk_name}/${k.label}/${k.unicode}`);
	expect(kl.length === 5, `押したキーが出る: ${kl.join(' ')}`);
	await page.key('Escape');
	await page.key('Escape');
	expect(!!(await page.waitState((s) => s.screen === 'title', 3000)), 'Esc 2 回でタイトルへ');
	const errs = page.errors();
	expect(errs.length === 0, `コンソールのエラー ${errs.length} 件` + (errs.length ? ': ' + errs.map((e) => e.text).slice(0, 5).join(' | ') : ''));
} finally {
	await page.close();
	site.stop();
}
console.log(failureCount() === 0 ? '全部 OK' : `${failureCount()} 件 NG`);
process.exit(failureCount() === 0 ? 0 : 1);
