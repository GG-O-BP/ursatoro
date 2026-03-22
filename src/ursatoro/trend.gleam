import bigdecimal.{type BigDecimal}
import bigdecimal/rounding
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import ursatoro/candle.{type Candle}
import ursatoro/util.{type IndicatorError}

// ── MACD result type ────────────────────────────────────────────────

pub type MacdResult {
  MacdResult(macd_line: Float, signal_line: Float, histogram: Float)
}

// ── ADX result type [AMAB: §3 Average Directional Index] ────────────
// adx: trend strength (0-100), direction-neutral.
// plus_di: +DI (bullish directional indicator), minus_di: -DI (bearish).
// ADX > 25 = strong trend, ADX < 20 = no trend.

pub type AdxResult {
  AdxResult(adx: Float, plus_di: Float, minus_di: Float)
}

// ── Donchian Channel result type [CCT: §3 breakout detection] ───────
// upper: highest high over N periods, lower: lowest low, mid: (upper+lower)/2.
// Price at upper = bullish breakout, price at lower = bearish breakout.

pub type DonchianResult {
  DonchianResult(upper: Float, lower: Float, mid: Float)
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

// ── ADX (Average Directional Index) ─────────────────────────────────
// [AMAB: §3 Quantitative Agent — ADX for trend strength confirmation]
// Algorithm: +DM/-DM from consecutive candle highs/lows →
// Wilder smooth +DM, -DM, TR over `period` → +DI = 100×smooth(+DM)/smooth(TR) →
// DX = 100×|+DI - -DI|/(+DI + -DI) → ADX = Wilder smooth of DX over `period`.
// Requires period×2+1 candles for two rounds of Wilder smoothing.

pub fn adx(
  candles: List(Candle),
  period: Int,
) -> Result(List(AdxResult), IndicatorError) {
  use _ <- result.try(util.validate_period(period))
  // Need period*2 + 1 candles for two rounds of Wilder smoothing
  use _ <- result.try(util.validate_length(candles, period * 2 + 1))
  let period_bd = util.int_to_bd(period)
  let period_minus_one = util.int_to_bd(period - 1)
  let hundred = util.hundred()
  let zero = bigdecimal.zero()

  // 1. Compute +DM, -DM, TR for each consecutive candle pair
  let dm_tr_list = compute_dm_tr(candles)

  // 2. First smoothed values = sum of first `period` entries
  let initial = list.take(dm_tr_list, period)
  let remaining = list.drop(dm_tr_list, period)

  let first_smooth_plus_dm = list.fold(initial, zero, fn(acc, x) {
    bigdecimal.add(acc, x.0)
  })
  let first_smooth_minus_dm = list.fold(initial, zero, fn(acc, x) {
    bigdecimal.add(acc, x.1)
  })
  let first_smooth_tr = list.fold(initial, zero, fn(acc, x) {
    bigdecimal.add(acc, x.2)
  })

  // 3. Wilder-smooth +DM, -DM, TR; compute +DI, -DI, DX
  let #(dx_list, _, _, _) =
    list.fold(remaining, #(
      [compute_dx(first_smooth_plus_dm, first_smooth_minus_dm, first_smooth_tr, hundred, zero)],
      first_smooth_plus_dm,
      first_smooth_minus_dm,
      first_smooth_tr,
    ), fn(acc, entry) {
      let #(dxs, prev_pdm, prev_mdm, prev_tr) = acc
      // Wilder smooth: new = prev × (period-1)/period + current/period
      // Simplified: new = (prev × (period-1) + current) / period
      let smooth_pdm = bigdecimal.divide(
        bigdecimal.add(bigdecimal.multiply(prev_pdm, period_minus_one), entry.0),
        by: period_bd,
        rounding: rounding.HalfUp,
      )
      let smooth_mdm = bigdecimal.divide(
        bigdecimal.add(bigdecimal.multiply(prev_mdm, period_minus_one), entry.1),
        by: period_bd,
        rounding: rounding.HalfUp,
      )
      let smooth_tr = bigdecimal.divide(
        bigdecimal.add(bigdecimal.multiply(prev_tr, period_minus_one), entry.2),
        by: period_bd,
        rounding: rounding.HalfUp,
      )
      let dx = compute_dx(smooth_pdm, smooth_mdm, smooth_tr, hundred, zero)
      #([dx, ..dxs], smooth_pdm, smooth_mdm, smooth_tr)
    })

  // dx_list is in reverse order; reverse and extract DX values for ADX smoothing
  let ordered_dx = list.reverse(dx_list)

  // 4. ADX = Wilder smoothing of DX over `period`
  let dx_values = list.map(ordered_dx, fn(d) { d.0 })
  let initial_dx = list.take(dx_values, period)
  let remaining_dx = list.drop(dx_values, period)

  case list.length(initial_dx) >= period {
    False -> Ok([])
    True -> {
      let first_adx = case util.bd_mean(initial_dx) {
        Ok(m) -> m
        Error(_) -> zero
      }
      let initial_result = list.drop(ordered_dx, period - 1)
      let first_dx_entry = case list.first(list.drop(ordered_dx, period - 1)) {
        Ok(e) -> e
        Error(_) -> #(zero, zero, zero)
      }

      let #(adx_results, _) =
        list.fold(remaining_dx, #(
          [AdxResult(
            adx: util.bd_to_float(first_adx),
            plus_di: util.bd_to_float(first_dx_entry.1),
            minus_di: util.bd_to_float(first_dx_entry.2),
          )],
          first_adx,
        ), fn(acc, dx_bd) {
          let #(results, prev_adx) = acc
          let new_adx = bigdecimal.divide(
            bigdecimal.add(
              bigdecimal.multiply(prev_adx, period_minus_one),
              dx_bd,
            ),
            by: period_bd,
            rounding: rounding.HalfUp,
          )
          // Find the corresponding +DI/-DI for this position
          let idx = list.length(results)
          let entry = case list.drop(initial_result, idx) {
            [e, ..] -> e
            [] -> #(zero, zero, zero)
          }
          let r = AdxResult(
            adx: util.bd_to_float(new_adx),
            plus_di: util.bd_to_float(entry.1),
            minus_di: util.bd_to_float(entry.2),
          )
          #([r, ..results], new_adx)
        })
      Ok(list.reverse(adx_results))
    }
  }
}

/// Compute directional movement and true range for consecutive candle pairs.
fn compute_dm_tr(
  candles: List(Candle),
) -> List(#(BigDecimal, BigDecimal, BigDecimal)) {
  let zero = bigdecimal.zero()
  case candles {
    [] | [_] -> []
    [first, ..rest] -> {
      let #(results, _) =
        list.fold(rest, #([], first), fn(acc, current) {
          let #(rs, prev) = acc
          let high_diff = bigdecimal.subtract(candle.high(current), candle.high(prev))
          let low_diff = bigdecimal.subtract(candle.low(prev), candle.low(current))
          // +DM = high_diff if > low_diff and > 0, else 0
          // -DM = low_diff if > high_diff and > 0, else 0
          let #(plus_dm, minus_dm) = case
            bigdecimal.compare(high_diff, low_diff)
          {
            order.Gt ->
              case bigdecimal.compare(high_diff, zero) {
                order.Gt -> #(high_diff, zero)
                _ -> #(zero, zero)
              }
            order.Lt ->
              case bigdecimal.compare(low_diff, zero) {
                order.Gt -> #(zero, low_diff)
                _ -> #(zero, zero)
              }
            order.Eq -> #(zero, zero)
          }
          let tr = util.true_range(prev, current)
          #([#(plus_dm, minus_dm, tr), ..rs], current)
        })
      list.reverse(results)
    }
  }
}

/// Compute DX and +DI/-DI from smoothed values.
/// Returns #(DX_bd, +DI_bd, -DI_bd)
fn compute_dx(
  smooth_pdm: BigDecimal,
  smooth_mdm: BigDecimal,
  smooth_tr: BigDecimal,
  hundred: BigDecimal,
  zero: BigDecimal,
) -> #(BigDecimal, BigDecimal, BigDecimal) {
  case bigdecimal.compare(smooth_tr, zero) {
    order.Gt -> {
      let plus_di = bigdecimal.divide(
        bigdecimal.multiply(smooth_pdm, hundred),
        by: smooth_tr,
        rounding: rounding.HalfUp,
      )
      let minus_di = bigdecimal.divide(
        bigdecimal.multiply(smooth_mdm, hundred),
        by: smooth_tr,
        rounding: rounding.HalfUp,
      )
      let di_sum = bigdecimal.add(plus_di, minus_di)
      let di_diff = util.bd_abs(bigdecimal.subtract(plus_di, minus_di))
      let dx = case bigdecimal.compare(di_sum, zero) {
        order.Gt ->
          bigdecimal.divide(
            bigdecimal.multiply(di_diff, hundred),
            by: di_sum,
            rounding: rounding.HalfUp,
          )
        _ -> zero
      }
      #(dx, plus_di, minus_di)
    }
    _ -> #(zero, zero, zero)
  }
}

// ── Donchian Channel ────────────────────────────────────────────────
// [CCT: §3 Donchian Channel breakout — Sharpe 1.31, CAGR 27-30% on BTC]
// Upper = max(High_{t-N..t}), Lower = min(Low_{t-N..t}), Mid = (Upper+Lower)/2.
// Entry: close hits upper (long) or lower (short). Sliding window computation.

pub fn donchian_channel(
  candles: List(Candle),
  period: Int,
) -> Result(List(DonchianResult), IndicatorError) {
  use _ <- result.try(util.validate_period(period))
  use _ <- result.try(util.validate_length(candles, period))
  let two = util.int_to_bd(2)

  // Sliding window computation
  let len = list.length(candles)
  let results =
    int.range(from: 0, to: len - period, with: [], run: fn(acc, start) {
      let window = list.take(list.drop(candles, start), period)
      let highs = list.map(window, candle.high)
      let lows = list.map(window, candle.low)
      let upper = list.fold(highs, bigdecimal.zero(), util.bd_max)
      let lower = list.fold(lows, case lows {
        [first, ..] -> first
        [] -> bigdecimal.zero()
      }, util.bd_min)
      let mid = bigdecimal.divide(
        bigdecimal.add(upper, lower),
        by: two,
        rounding: rounding.HalfUp,
      )
      [DonchianResult(
        upper: util.bd_to_float(upper),
        lower: util.bd_to_float(lower),
        mid: util.bd_to_float(mid),
      ), ..acc]
    })
  Ok(list.reverse(results))
}

// ── Helpers ─────────────────────────────────────────────────────────

fn list_split(items: List(a), at: Int) -> #(List(a), List(a)) {
  #(list.take(items, at), list.drop(items, at))
}
