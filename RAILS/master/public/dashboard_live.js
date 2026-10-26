const grid = document.getElementById('mission-grid');
const L = (key, fallback = '') => grid?.dataset[key] || fallback;

// Authentication failure is terminal for this page; transient failures are
// visible and keep retrying. A hidden tab spends no request budget.
const refreshState = document.getElementById('refresh-state');
let inFlight = false;
let terminal = false;

function closeDoor() {
  terminal = true;
  clearInterval(timer);
  const note = document.createElement('p');
  note.textContent = L('i18nAuth', 'authentication required');
  grid.replaceChildren(note);
  refreshState.textContent = L('i18nAuth', 'authentication required');
}

async function refresh() {
  if (terminal || inFlight || document.hidden) return;
  inFlight = true;
  try {
    const r = await fetch('/dashboard/live', {
      headers: { Accept: 'application/json' },
      cache: 'no-store'
    });
    if (r.status === 401 || r.status === 403) { closeDoor(); return; }

    const d = await r.json();
    if (!r.ok || d.error) {
      const reason = d.error || `HTTP ${r.status}`;
      document.getElementById('status').textContent =
        `${L('i18nUnavailable', 'status unavailable')}: ${reason}`;
      refreshState.textContent = L('i18nRefreshFailed', 'live data unavailable; retrying');
      return;
    }

    const none = L('i18nBreakersNone', 'none');
    const m = d.mission || {};
    document.getElementById('status').textContent = [
      `${L('labelModel', 'model')}: ${d.model}`,
      `mission: ${m.id || 'none'}`,
      `mission state: ${m.state || 'idle'} / ${m.stage || '—'}`,
      `effort: ${m.effort || '—'}`,
      `${L('labelCtx', 'ctx')}: ${d.tokens} ${L('labelTokens', 'tokens')}`,
      `${L('labelCost', 'cost')}: $${Number(d.cost || 0).toFixed(4)}`,
      `${L('labelAgentPool', 'agent pool')}: ${d.agent_pool} active`,
      `${L('labelBreakers', 'breakers')}: ${(d.open_breakers || []).join(', ') || none}`
    ].join('\n');

    const rtk = d.rtk || {};
    document.getElementById('rtk').textContent = [
      `${L('labelCommands', 'commands')}: ${rtk.commands || 0}`,
      `${L('labelSaved', 'saved')}: ${rtk.saved_pct || 0}%`,
      `${L('labelBytes', 'bytes')}: ${rtk.bytes_out || 0} / ${rtk.bytes_in || 0}`
    ].join('\n');
    document.getElementById('plan').textContent = d.active_plan || L('i18nNone', '(none)');
    document.getElementById('rsi').textContent = (d.rsi_inbox || []).map(i => `${i.path}\n${i.excerpt}`).join('\n\n') || L('i18nEmpty', '(empty)');
    document.getElementById('skills').textContent = (d.skills || []).join('\n') || L('i18nNone', '(none)');

    const p = d.context_pressure || {};
    document.getElementById('pressure').textContent = [
      `${L('labelBand', 'band')}: ${p.band || 'ok'}`,
      `${L('labelTokens', 'tokens')}: ${p.tokens || 0} / ${p.limit || 0}`,
      `${L('labelPct', 'pct')}: ${p.pct || 0}%`,
      `${L('labelHeadroom', 'headroom')}: ${p.headroom || 0}`
    ].join('\n');

    const ph = d.provider_health || {};
    document.getElementById('providers').textContent = [
      `${L('labelStatus', 'status')}: ${ph.status || 'unknown'}`,
      `${L('labelOpenBreakers', 'open breakers')}: ${(ph.open_breakers || []).join(', ') || none}`,
      `${L('labelAgentPool', 'agent pool')}: ${ph.agent_pool || 0}`
    ].join('\n');

    document.getElementById('repair').textContent = (d.repair_queue || []).map((item) => {
      const recent = (item.recent || []).join('\n  ');
      return `${item.path} (${item.count || 0} bytes)\n  ${recent}`;
    }).join('\n\n') || L('i18nEmpty', '(empty)');
    document.getElementById('bus').textContent = (d.bus_events || []).slice(-12).map(e => JSON.stringify(e)).join('\n') || L('i18nQuiet', '(quiet)');
    refreshState.textContent = `${L('i18nUpdated', 'updated')}: ${new Date().toLocaleTimeString()}`;
  } catch (error) {
    const reason = error?.message ? error.message : 'network error';
    document.getElementById('status').textContent =
      `${L('i18nUnavailable', 'status unavailable')}: ${reason}`;
    refreshState.textContent = L('i18nRefreshFailed', 'live data unavailable; retrying');
  } finally {
    inFlight = false;
  }
}
const timer = setInterval(() => { if (!document.hidden) refresh(); }, 8000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
refresh();
