// A reader scrolled back through a conversation log, then the log reconnects
// (the controller disconnects and connects, as a Turbo refresh or a stream
// re-attach does) and a new line arrives. The reader must stay where they were,
// be told a line arrived, and reach it with one press. The log is padded with
// copies of its own last line until it scrolls; nothing is sent to the server.
(async () => {
  const tick = () => new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 40)));
  const log = document.querySelector('[data-controller~="conversation-log"]');
  if (!log) return { found: false };
  const lines = [...log.children].filter((li) => li.querySelector('[data-sender-id]'));
  const sample = lines[lines.length - 1];
  if (!sample) return { found: true, scrollable: false, lines: 0 };
  let padded = 0;
  while (log.scrollHeight - log.clientHeight < 600 && padded < 120) { log.appendChild(sample.cloneNode(true)); padded++; }
  await tick();
  if (log.scrollHeight - log.clientHeight < 300) return { found: true, scrollable: false, padded };
  log.scrollTop = Math.round((log.scrollHeight - log.clientHeight) / 2);
  log.dispatchEvent(new Event('scroll'));
  await tick();
  const before = log.scrollTop;
  const controllers = log.getAttribute('data-controller');
  log.setAttribute('data-controller', controllers.split(/\s+/).filter((name) => name !== 'conversation-log').join(' '));
  await tick();
  log.setAttribute('data-controller', controllers);
  await tick();
  const reconnected = log.scrollTop;
  log.appendChild(sample.cloneNode(true));
  await tick();
  const arrived = log.scrollTop;
  const pill = log.parentElement.querySelector('.conversation_unread_pill');
  const pillShown = pill?.getBoundingClientRect().height > 0;
  if (pill) { pill.click(); await tick(); }
  return {
    found: true, scrollable: true, padded, before, reconnected, arrived, pill: pillShown,
    tail_gap: Math.round(log.scrollHeight - log.scrollTop - log.clientHeight),
    pill_left: !!log.parentElement.querySelector('.conversation_unread_pill')
  };
})()
