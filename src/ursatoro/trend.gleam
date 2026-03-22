import bigdecimal.{type BigDecimal}
import bigdecimal/rounding
import gleam/list
import gleam/result
import ursatoro/candle.{type Candle}
import ursatoro/util.{type IndicatorError}

// ── MACD result type ────────────────────────────────────────────────

pub type MacdResult {
  MacdResult(macd_line: Float, signal_line: Float, histogram: Float)
}

// ── SMA ─────────────────────────────────────────────────────────────

pub fn sma(
  candles: List(Candle),
  period: Int,
) -> Result(List(Float), IndicatorError) {
  let closes = list.map(candles, candle.close)
  use values <- result.try(util.sma_values(closes, period))
  Ok(util.bds_to_floats(values))
}

// ── EMA ─────────────────────────────────────────────────────────────

pub fn ema(
  candles: List(Candle),
  period: Int,
) -> Result(List(Float), IndicatorError) {
  let closes = list.map(candles, candle.close)
  use values <- result.try(ema_from_values(closes, period))
  Ok(util.bds_to_floats(values))
}

fn ema_from_values(
  values: List(BigDecimal),
  period: Int,
) -> Result(List(BigDecimal), IndicatorError) {
  use _ <- result.try(util.validate_period(period))
  use _ <- result.try(util.validate_length(values, period))
  let k = ema_multiplier(period)
  let one_minus_k = bigdecimal.subtract(bigdecimal.one(), k)
  // Split into initial period and rest
  let #(initial, rest) = list_split(values, period)
  // First EMA = SMA of initial period
  use first_ema <- result.try(util.bd_mean(initial))
  // Fold over remaining values, computing EMA
  let #(results, _) =
    list.fold(rest, #([first_ema], first_ema), fn(acc, value) {
      let #(results, prev_ema) = acc
      // EMA = value * k + prev_ema * (1 - k)
      let new_ema =
        bigdecimal.add(
          bigdecimal.multiply(value, k),
          bigdecimal.multiply(prev_ema, one_minus_k),
        )
      #([new_ema, ..results], new_ema)
    })
  Ok(list.reverse(results))
}

fn ema_multiplier(period: Int) -> BigDecimal {
  let two = util.int_to_bd(2)
  let period_plus_one = util.int_to_bd(period + 1)
  bigdecimal.divide(two, by: period_plus_one, rounding: rounding.HalfUp)
}

// ── MACD ────────────────────────────────────────────────────────────

pub fn macd(
  candles: List(Candle),
  fast: Int,
  slow: Int,
  signal: Int,
) -> Result(List(MacdResult), IndicatorError) {
  use _ <- result.try(util.validate_period(fast))
  use _ <- result.try(util.validate_period(slow))
  use _ <- result.try(util.validate_period(signal))
  let closes = list.map(candles, candle.close)
  // Need at least `slow` candles for the slow EMA, plus `signal - 1` for signal line
  use _ <- result.try(util.validate_length(closes, slow + signal - 1))
  // Compute fast and slow EMAs
  use fast_ema <- result.try(ema_from_values(closes, fast))
  use slow_ema <- result.try(ema_from_values(closes, slow))
  // Align: fast_ema is longer, trim its head to match slow_ema length
  let fast_len = list.length(fast_ema)
  let slow_len = list.length(slow_ema)
  let offset = fast_len - slow_len
  let aligned_fast = list.drop(fast_ema, offset)
  // MACD line = fast EMA - slow EMA
  let macd_line = list.map2(aligned_fast, slow_ema, bigdecimal.subtract)
  // Signal line = EMA of MACD line
  use signal_ema <- result.try(ema_from_values(macd_line, signal))
  // Align MACD line to signal line length
  let macd_len = list.length(macd_line)
  let signal_len = list.length(signal_ema)
  let macd_offset = macd_len - signal_len
  let aligned_macd = list.drop(macd_line, macd_offset)
  // Build results: histogram = MACD - signal
  let results =
    list.map2(aligned_macd, signal_ema, fn(m, s) {
      let histogram = bigdecimal.subtract(m, s)
      MacdResult(
        macd_line: util.bd_to_float(m),
        signal_line: util.bd_to_float(s),
        histogram: util.bd_to_float(histogram),
      )
    })
  Ok(results)
}

// ── Helpers ─────────────────────────────────────────────────────────

fn list_split(items: List(a), at: Int) -> #(List(a), List(a)) {
  #(list.take(items, at), list.drop(items, at))
}
