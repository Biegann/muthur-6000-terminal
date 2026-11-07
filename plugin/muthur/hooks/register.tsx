// MU/TH/UR 6000: mod Claude Code (część pluginu „muthur”).
//
// - spinner: zamiast wielokropka blokowy kursor ▮ jak na ekranie MATKI,
// - linia kończąca turę: „TRANSMISJA ZAKOŃCZONA · 3 s” zamiast „Baked for 3s”,
// - odpowiedź w trybie MATKI: etykieta „▮ MU/TH/UR 6000” i podkreślony nagłówek interfejsu,
// - /muthur: panel „POKÓJ MATKI” ze ścianą migających bursztynowych lampek
//   (szybciej, gdy Claude pracuje), stanem interfejsu i podsumowaniem ostatniego
//   zapytania (czas, tokeny wejścia, wyjścia i pamięci podręcznej).
//
// Kolory pochodzą z config/palette.json (skalibrowane na klatkach filmu);
// test tests/python/test_mod_colors.py pilnuje, żeby się zgadzały.
import type { Register, TurnUsage } from 'claude-code'

// Środowisko modu ma kodowanie base64 tablic bajtów (por. RasterProps w typach silnika),
// a biblioteka TypeScript 5.9 jeszcze go nie deklaruje.
declare global {
  interface Uint8Array {
    toBase64(): string
  }
  interface Uint8ArrayConstructor {
    fromBase64(text: string): Uint8Array
  }
}

export const COLORS = {
  phosphor: '#38D296',
  phosphorBright: '#B4F5CE',
  phosphorDim: '#1F7A5C',
  flare: '#D4EC66',
  lamp: '#F9D655',
  lampBright: '#FFF2A8',
  lampOff: '#3A2A1C',
} as const

export const HEADER = 'INTERFEJS 2037 · ZAPYTANIE PRZYJĘTE'
const HEADER_LINE = /^\s*`?INTERFEJS 2037 · ZAPYTANIE PRZYJĘTE`?[ \t]*(\r?\n)*/
const PANE = 'muthur-room'
const SQUARE = 0x25a0 // ■
const DEFAULT = 0x01000000 // domyślny kolor terminala (bit 24)

const hex = (c: string) => parseInt(c.slice(1), 16)

/** Zdejmuje nagłówek interfejsu z odpowiedzi MATKI; null, gdy to nie tryb MATKI. */
export function splitHeader(text: string): string | null {
  const m = HEADER_LINE.exec(text)
  return m ? text.slice(m[0].length) : null
}

/** 3200 -> „3 s”, 64000 -> „1 min 4 s”. */
export function formatDuration(ms: number): string {
  const s = Math.max(0, Math.round(ms / 1000))
  const min = Math.floor(s / 60)
  return min > 0 ? `${min} min ${s % 60} s` : `${s} s`
}

/** 46234 -> „46 234” (grupy po trzy cyfry, jak w polskim zapisie). */
export function formatCount(n: number): string {
  return String(Math.max(0, Math.round(n))).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')
}

/** Ostatnie zapytanie głównej pętli: czas, powód końca i tokeny (gdy silnik je policzył). */
export type LastInquiry = {
  durationMs: number
  isAborted: boolean
  isError: boolean
  usage?: TurnUsage
}

/** Wiersze podsumowania ostatniego zapytania w panelu (krótkie: panel bywa wąski). */
export function inquirySummary(last: LastInquiry | null): string[] {
  if (last === null) return ['OSTATNIE ZAPYTANIE · BRAK DANYCH']
  const end = last.isAborted ? 'PRZERWANE' : last.isError ? 'BŁĄD' : 'ZAKOŃCZONE'
  const head = `OSTATNIE ZAPYTANIE · ${end} · ${formatDuration(last.durationMs)}`
  const u = last.usage
  if (!u) return [head, 'TOKENY · BRAK DANYCH']
  const input = u.input_tokens + u.cache_read_input_tokens + u.cache_creation_input_tokens
  return [
    head,
    `TOKENY · WEJŚCIE ${formatCount(input)} · WYJŚCIE ${formatCount(u.output_tokens)}`,
    `PAMIĘĆ PODRĘCZNA · ODCZYT ${formatCount(u.cache_read_input_tokens)} · ZAPIS ${formatCount(u.cache_creation_input_tokens)}`,
  ]
}

/** Ściana lampek: stan każdej lampki (0 zgaszona, 1 zapalona, 2 jasna). */
export class LightWall {
  columns = 0
  rows = 0
  state: Uint8Array = new Uint8Array(0)
  private seed = 2037

  private random(): number {
    // Deterministyczny generator (xorshift), żeby testy były powtarzalne.
    let x = this.seed
    x ^= x << 13
    x ^= x >>> 17
    x ^= x << 5
    this.seed = x >>> 0
    return this.seed / 0x100000000
  }

  resize(columns: number, rows: number): void {
    if (columns === this.columns && rows === this.rows) return
    this.columns = columns
    this.rows = rows
    this.state = new Uint8Array(Math.ceil(columns / 2) * rows)
    for (let i = 0; i < this.state.length; i++) this.state[i] = this.random() < 0.7 ? 1 : 0
  }

  /** Zmienia losowo część lampek: share = ułamek lampek na krok. */
  step(share: number): void {
    const n = Math.max(1, Math.round(this.state.length * share))
    for (let k = 0; k < n; k++) {
      const i = Math.floor(this.random() * this.state.length)
      const r = this.random()
      this.state[i] = r < 0.3 ? 0 : r < 0.85 ? 1 : 2
    }
  }

  /** Komórki Rastra: lampka ■ w co drugiej kolumnie, spacja pomiędzy. */
  cells(): string {
    const words = new Uint32Array(this.columns * this.rows * 3)
    const lampColors = [hex(COLORS.lampOff), hex(COLORS.lamp), hex(COLORS.lampBright)]
    const lampsPerRow = Math.ceil(this.columns / 2)
    for (let r = 0; r < this.rows; r++) {
      for (let c = 0; c < this.columns; c++) {
        const at = (r * this.columns + c) * 3
        const isLamp = c % 2 === 0
        words[at] = isLamp ? SQUARE : 0x20
        words[at + 1] = isLamp ? (lampColors[this.state[r * lampsPerRow + c / 2] ?? 0] ?? DEFAULT) : DEFAULT
        words[at + 2] = DEFAULT
      }
    }
    return new Uint8Array(words.buffer).toBase64()
  }
}

export const register: Register = on => {
  const wall = new LightWall()
  let isWorking = false
  let isOpen = false
  let lastHealAt = 0
  let last: LastInquiry | null = null

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'muthur',
      description: 'POKÓJ MATKI: panel ze ścianą lampek MU/TH/UR 6000 (otwiera i zamyka)',
    })
    // Timer lampek żyje przez całą sesję. Uruchomiony w hooku rysującym panel ginął razem
    // z tamtym wywołaniem po przerysowaniu panelu (po wysłaniu zapytania) i lampki zamierały.
    $.clock.every(120, async () => {
      if (!isOpen || wall.columns === 0) return
      wall.step(isWorking ? 0.12 : 0.02)
      const result = await $.ui.blit({
        requestId: PANE, key: 'wall', cells: wall.cells(), columns: wall.columns, rows: wall.rows,
      })
      // Samonaprawa: odrzucone przemalowanie (np. panel przerysowany w innym rozmiarze)
      // kończy się przerysowaniem panelu, najwyżej raz na sekundę.
      if ('deny' in result) {
        const now = await $.clock.now()
        if (now - lastHealAt >= 1000) {
          lastHealAt = now
          $.ui.invalidate('ui.render')
        }
      }
    })
    return next(e)
  })

  on('command.run', { command: 'muthur' }, async $ => {
    if (isOpen) {
      await $.ui.close({ id: PANE })
      return { text: 'MU/TH/UR 6000: POKÓJ MATKI ZAMKNIĘTY.' }
    }
    const opened = await $.ui.open({ id: PANE, title: 'POKÓJ MATKI' })
    return {
      text: opened.isPlaced
        ? 'MU/TH/UR 6000: POKÓJ MATKI OTWARTY.'
        : 'MU/TH/UR 6000: POKÓJ MATKI CZEKA NA MIEJSCE (poszerz okno terminala).',
    }
  })

  // Lampki migają szybciej, gdy Claude pracuje. .catch: błąd modu nigdy nie zatrzyma promptu.
  on('prompt.submit', ($, e, next) => {
    isWorking = true
    if (isOpen) $.ui.invalidate('ui.render')
    return next(e)
  }).catch(($, e, next) => next(e))
  // Tylko główna pętla: koniec tury subagenta nie kończy zapytania użytkownika.
  on('turn.complete', ($, e, next) => {
    if (e.agentId === undefined) {
      isWorking = false
      last = {
        durationMs: e.durationMs,
        isAborted: e.isAborted,
        isError: e.reason === 'error',
        usage: e.usage,
      }
      if (isOpen) $.ui.invalidate('ui.render')
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.close', ($, e, next) => {
    if (e.id === PANE) isOpen = false
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    isOpen = true
    const columns = Math.max(4, Math.min(512, e.props.bodyColumns))
    const summary = inquirySummary(last)
    const rows = Math.max(3, Math.min(12, e.props.scroll.bodyRows - 2 - summary.length))
    wall.resize(columns, rows)
    const status = isWorking ? 'PRZETWARZANIE' : 'GOTOWY DO ZAPYTAŃ'
    if (e.surface === 'terminal') {
      const { Box, Raster, Text } = $.ui.resolve(e)
      return (
        <Box flexDirection="column">
          <Raster key="wall" columns={wall.columns} rows={wall.rows} cells={wall.cells()} />
          <Text color={COLORS.phosphorBright}>
            MU/TH/UR 6000 <Text color={isWorking ? COLORS.flare : COLORS.phosphor}>· {status}</Text>
          </Text>
          {summary.map(line => (
            <Text color={COLORS.phosphor}>{line}</Text>
          ))}
        </Box>
      )
    }
    // Inne powierzchnie nie mają Rastra: lampki jako tekst.
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        <Text color={COLORS.lamp}>{'■ '.repeat(Math.ceil(columns / 2)).trimEnd()}</Text>
        <Text color={COLORS.phosphorBright}>MU/TH/UR 6000 · {status}</Text>
        {summary.map(line => (
          <Text color={COLORS.phosphor}>{line}</Text>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'Spinner' }, ($, e, next) =>
    next({ ...e, props: { ...e.props, suffix: ' ▮' } }),
  )

  on('ui.render', { component: 'TurnDuration' }, async ($, e, next) => {
    if (e.props.isExpanded) return next(e)
    const { Text } = $.ui.resolve(e)
    return (
      <Text color={COLORS.phosphorDim}>
        TRANSMISJA ZAKOŃCZONA · {formatDuration(e.props.durationMs)}
      </Text>
    )
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const rest = e.props.isFirstOfReply ? splitHeader(e.props.text) : null
    if (rest === null) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const body = await next({ ...e, props: { ...e.props, text: rest } })
    // Jeden wiersz z odstępem przed nim: osobny pierwszy wiersz etykiety ginął
    // pod wierszem pytania użytkownika (brak odstępu, jaki mają zwykłe wiadomości).
    return (
      <Box flexDirection="column" marginTop={1}>
        <Text>
          <Text color={COLORS.flare}>▮ MU/TH/UR 6000 </Text>
          <Text color={COLORS.phosphorBright} underline>
            {HEADER}
          </Text>
        </Text>
        {body}
      </Box>
    )
  })
}
