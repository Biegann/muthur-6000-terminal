import { expect, mock, test } from 'claude-code/testing'

import { formatCount, formatDuration, HEADER, inquirySummary, LightWall, splitHeader } from '../hooks/register'

const PLUGIN = 'muthur'

test('nagłówek MATKI jest rozpoznawany i zdejmowany z odpowiedzi', () => {
  expect(splitHeader(`${HEADER}\n\nANALIZA ZAKOŃCZONA.`)).toBe('ANALIZA ZAKOŃCZONA.')
  expect(splitHeader('`' + HEADER + '`\nOK')).toBe('OK')
  expect(splitHeader('Zwykła odpowiedź')).toBe(null)
  expect(splitHeader(`Tekst, a dalej ${HEADER}`)).toBe(null)
})

test('czas tury po polsku', () => {
  expect(formatDuration(3200)).toBe('3 s')
  expect(formatDuration(64000)).toBe('1 min 4 s')
})

test('ściana lampek: ■ w co drugiej kolumnie, w kolorach lampek', () => {
  const wall = new LightWall()
  wall.resize(5, 2)
  const bytes = Uint8Array.fromBase64(wall.cells())
  const words = new Uint32Array(bytes.buffer)
  expect(words.length).toBe(5 * 2 * 3)
  expect(words[0]).toBe(0x25a0)
  expect(words[3]).toBe(0x20)
  expect([0x3a2a1c, 0xf9d655, 0xfff2a8]).toContain(words[1])
  wall.step(1)
  expect(Uint8Array.fromBase64(wall.cells()).length).toBe(5 * 2 * 3 * 4)
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`spinner kończy się kursorem MATKI ▮ (${surface})`, async ($, on) => {
    on('ui.render', { component: 'Spinner' }, ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>{`${e.props.word}${e.props.suffix}`}</Text>
    })
    const ui = await $.ui.mount({
      plugin: PLUGIN,
      surface,
      component: 'Spinner',
      props: { word: 'OBLICZANIE', message: null, suffix: '…', mode: 'thinking' },
    })
    expect((await ui.find({ type: 'Text', text: /OBLICZANIE/ }))?.text).toBe('OBLICZANIE ▮')
    await ui.unmount()
  })

  test(`odpowiedź MATKI: etykieta i nagłówek nad treścią bez nagłówka (${surface})`, async ($, on) => {
    on('ui.render', { component: 'AssistantMessage' }, ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>{`silnik: ${e.props.text}`}</Text>
    })
    const ui = await $.ui.mount({
      plugin: PLUGIN,
      surface,
      component: 'AssistantMessage',
      props: { text: `${HEADER}\n\nANALIZA ZAKOŃCZONA.`, isFirstOfReply: true },
    })
    // Etykieta i nagłówek w jednym wierszu.
    expect((await ui.find({ type: 'Text', text: /^▮ MU\/TH\/UR 6000 INTERFEJS/ }))?.text).toBe(`▮ MU/TH/UR 6000 ${HEADER}`)
    expect((await ui.find({ type: 'Text', text: /silnik/ }))?.text).toBe('silnik: ANALIZA ZAKOŃCZONA.')
    await ui.unmount()
  })

  test(`zwykła odpowiedź zostaje bez zmian (${surface})`, async ($, on) => {
    on('ui.render', { component: 'AssistantMessage' }, ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>{`silnik: ${e.props.text}`}</Text>
    })
    const ui = await $.ui.mount({
      plugin: PLUGIN,
      surface,
      component: 'AssistantMessage',
      props: { text: 'Gotowe, testy przechodzą.', isFirstOfReply: true },
    })
    expect((await ui.find({ type: 'Text', text: /silnik/ }))?.text).toBe('silnik: Gotowe, testy przechodzą.')
    expect(await ui.find({ type: 'Text', text: /MU\/TH\/UR/ })).toBe(undefined)
    await ui.unmount()
  })
}

test('linia końca tury: TRANSMISJA ZAKOŃCZONA', async ($, on) => {
  const ui = await $.ui.mount({
    plugin: PLUGIN,
    surface: 'terminal',
    component: 'TurnDuration',
    props: { word: 'Baked', durationMs: 3200 },
  })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('TRANSMISJA ZAKOŃCZONA · 3 s')
  await ui.unmount()
})

test('/muthur otwiera POKÓJ MATKI, a panel pokazuje stan interfejsu', async ($, on) => {
  on('command.register', () => ({ value: { command: 'muthur' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const answer = await $.command.run({
    command: 'muthur',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: true, columns: 160 },
  })
  expect(answer.text).toBe('MU/TH/UR 6000: POKÓJ MATKI OTWARTY.')

  const pane = {
    plugin: PLUGIN,
    component: 'Pane',
    requestId: 'muthur-room',
    props: {
      title: 'POKÓJ MATKI',
      isFocused: false,
      bodyColumns: 40,
      placement: 'dock',
      scroll: { offset: 0, bodyRows: 14 },
      view: {},
    },
  } as const

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...pane, surface })
    expect((await ui.find({ type: 'Text', text: /MU\/TH\/UR 6000/ }))?.text).toBe('MU/TH/UR 6000 · GOTOWY DO ZAPYTAŃ')
    await ui.unmount()
  }

  await $.prompt.submit({ text: 'Matko, raport', wait: false, origin: { kind: 'composer' } })
  const ui = await $.ui.mount({ ...pane, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /MU\/TH\/UR 6000/ }))?.text).toBe('MU/TH/UR 6000 · PRZETWARZANIE')
  await ui.unmount()
})

test('lampki migają dalej po wysłaniu zapytania i po końcu tury (błąd: zamierały)', async ($, on) => {
  const clock = mock.clock(on)
  let blits = 0
  on('ui.blit', () => {
    blits += 1
    return { value: {} }
  })
  on('command.register', () => ({ value: { command: 'muthur' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.command.run({
    command: 'muthur',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: true, columns: 160 },
  })
  const pane = {
    plugin: PLUGIN,
    component: 'Pane',
    requestId: 'muthur-room',
    surface: 'terminal',
    props: {
      title: 'POKÓJ MATKI',
      isFocused: false,
      bodyColumns: 40,
      placement: 'inline',
      scroll: { offset: 0, bodyRows: 14 },
      view: {},
    },
  } as const

  const first = await $.ui.mount(pane)
  await clock.advance(1000)
  const beforePrompt = blits
  expect(beforePrompt).toBeGreaterThan(3)

  // Zapytanie przerysowuje panel (stan PRZETWARZANIE).
  await $.prompt.submit({ text: 'Matko, raport', wait: false, origin: { kind: 'composer' } })
  await first.unmount()
  const second = await $.ui.mount(pane)
  await clock.advance(1000)
  expect(blits - beforePrompt).toBeGreaterThan(3)
  await second.unmount()
})
test('odrzucone przemalowanie lampek kończy się przerysowaniem panelu (najwyżej raz na sekundę)', async ($, on) => {
  const clock = mock.clock(on)
  let heals = 0
  on('ui.blit', () => ({ value: { deny: 'not mounted' } }))
  on('ui.invalidate', () => {
    heals += 1
    return { value: undefined }
  })
  on('command.register', () => ({ value: { command: 'muthur' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.command.run({
    command: 'muthur',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: true, columns: 160 },
  })
  const ui = await $.ui.mount({
    plugin: PLUGIN,
    component: 'Pane',
    requestId: 'muthur-room',
    surface: 'terminal',
    props: {
      title: 'POKÓJ MATKI',
      isFocused: false,
      bodyColumns: 40,
      placement: 'inline',
      scroll: { offset: 0, bodyRows: 14 },
      view: {},
    },
  })
  heals = 0
  await clock.advance(3000)
  expect(heals).toBeGreaterThan(1)
  expect(heals).toBeLessThan(5)
  await ui.unmount()
})
test('liczby tokenów w grupach po trzy cyfry', () => {
  expect(formatCount(0)).toBe('0')
  expect(formatCount(999)).toBe('999')
  expect(formatCount(46234)).toBe('46 234')
  expect(formatCount(1234567)).toBe('1 234 567')
})

test('podsumowanie ostatniego zapytania: czas, tokeny, pamięć podręczna', () => {
  expect(inquirySummary(null)).toEqual(['OSTATNIE ZAPYTANIE · BRAK DANYCH'])
  const usage = {
    model: 'claude-opus-5-5',
    input_tokens: 1234,
    output_tokens: 567,
    cache_read_input_tokens: 45000,
    cache_creation_input_tokens: 1000,
  }
  expect(inquirySummary({ durationMs: 12000, isAborted: false, isError: false, usage })).toEqual([
    'OSTATNIE ZAPYTANIE · ZAKOŃCZONE · 12 s',
    'TOKENY · WEJŚCIE 47 234 · WYJŚCIE 567',
    'PAMIĘĆ PODRĘCZNA · ODCZYT 45 000 · ZAPIS 1 000',
  ])
  expect(inquirySummary({ durationMs: 3000, isAborted: true, isError: false })).toEqual([
    'OSTATNIE ZAPYTANIE · PRZERWANE · 3 s',
    'TOKENY · BRAK DANYCH',
  ])
})

test('panel pokazuje podsumowanie zapytania głównej pętli, nie subagenta', async ($, on) => {
  on('command.register', () => ({ value: { command: 'muthur' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.command.run({
    command: 'muthur',
    args: '',
    origin: { kind: 'composer' },
    presentation: { isFullscreen: true, columns: 160 },
  })
  const pane = {
    plugin: PLUGIN,
    component: 'Pane',
    requestId: 'muthur-room',
    props: {
      title: 'POKÓJ MATKI',
      isFocused: false,
      bodyColumns: 60,
      placement: 'dock',
      scroll: { offset: 0, bodyRows: 14 },
      view: {},
    },
  } as const

  await $.prompt.submit({ text: 'Matko, raport', wait: false, origin: { kind: 'composer' } })
  // Subagent kończy turę w trakcie zapytania: panel nadal przetwarza, bez podsumowania.
  await $.turn.complete({
    answer: 'raport subagenta',
    durationMs: 2000,
    isAborted: false,
    turnId: 't-agent',
    agentId: 'agent-1',
    reason: 'answer',
    usage: { model: 'm', input_tokens: 9, output_tokens: 9, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
  })
  const during = await $.ui.mount({ ...pane, surface: 'desktop' })
  expect((await during.find({ type: 'Text', text: /MU\/TH\/UR 6000/ }))?.text).toBe('MU/TH/UR 6000 · PRZETWARZANIE')
  expect((await during.find({ type: 'Text', text: /^OSTATNIE/ }))?.text).toBe('OSTATNIE ZAPYTANIE · BRAK DANYCH')
  await during.unmount()

  await $.turn.complete({
    answer: 'RAPORT GOTOWY.',
    durationMs: 64000,
    isAborted: false,
    turnId: 't-main',
    reason: 'answer',
    usage: { model: 'm', input_tokens: 1200, output_tokens: 3456, cache_read_input_tokens: 80000, cache_creation_input_tokens: 2000 },
  })
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...pane, surface })
    expect((await ui.find({ type: 'Text', text: /MU\/TH\/UR 6000/ }))?.text).toBe('MU/TH/UR 6000 · GOTOWY DO ZAPYTAŃ')
    expect((await ui.find({ type: 'Text', text: /^OSTATNIE/ }))?.text).toBe('OSTATNIE ZAPYTANIE · ZAKOŃCZONE · 1 min 4 s')
    expect((await ui.find({ type: 'Text', text: /^TOKENY/ }))?.text).toBe('TOKENY · WEJŚCIE 83 200 · WYJŚCIE 3 456')
    expect((await ui.find({ type: 'Text', text: /^PAMIĘĆ/ }))?.text).toBe('PAMIĘĆ PODRĘCZNA · ODCZYT 80 000 · ZAPIS 2 000')
    await ui.unmount()
  }
})
