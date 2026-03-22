// Market microstructure indicators.
// [Paper: MICRO - Microstructure & Market Dynamics]
// [Paper: EXPL - Explainable Crypto Microstructure]
//
// VPIN: "Most important predictive feature" for market dynamics
// Roll Measure: Liquidity proxy via price autocorrelation
// Amihud: Illiquidity proxy via price impact per volume

import gleam/float
import gleam/list
import gleam/result
import ursatoro/util.{type IndicatorError}

// ── Types ─────────────────────────────────────────────────────────

pub type TradeBar {
  TradeBar(
    buy_volume: Float,
    sell_volume: Float,
    total_volume: Float,
    price_change: Float,
  )
}

// ── VPIN ──────────────────────────────────────────────────────────
// Volume-Synchronized Probability of Informed Trading [MICRO]
// Formula: VPIN = (1/W) × Σ|sell_vol - buy_vol| / total_vol
// Crypto average VPIN = 0.45-0.47 (2x higher than equities)

pub fn vpin(
  trade_bars: List(TradeBar),
  window window: Int,
) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_period(window))
  use _ <- result.try(util.validate_length(trade_bars, window))
  Ok(sliding_vpin(trade_bars, window, []))
}

fn sliding_vpin(
  bars: List(TradeBar),
  window: Int,
  acc: List(Float),
) -> List(Float) {
  case list.length(bars) >= window {
    False -> list.reverse(acc)
    True -> {
      let window_bars = list.take(bars, window)
      let value = compute_vpin_window(window_bars, window)
      case list.rest(bars) {
        Ok(rest) -> sliding_vpin(rest, window, [value, ..acc])
        Error(_) -> list.reverse([value, ..acc])
      }
    }
  }
}

fn compute_vpin_window(bars: List(TradeBar), window: Int) -> Float {
  let sum =
    list.fold(bars, 0.0, fn(acc, bar) {
      case bar.total_volume >. 0.0 {
        True ->
          acc
          +. float.absolute_value(bar.sell_volume -. bar.buy_volume)
          /. bar.total_volume
        False -> acc
      }
    })
  let w = int_to_float(window)
  case w >. 0.0 {
    True -> sum /. w
    False -> 0.0
  }
}

// ── Roll Measure ──────────────────────────────────────────────────
// Liquidity proxy from price autocorrelation [MICRO]
// Formula: Roll = 2√|cov(ΔP_t, ΔP_{t-1})|

pub fn roll_measure(
  prices: List(Float),
  window window: Int,
) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_period(window))
  let min_len = window + 1
  use _ <- result.try(util.validate_length(prices, min_len))
  let changes = compute_changes(prices)
  Ok(sliding_roll(changes, window, []))
}

fn sliding_roll(
  changes: List(Float),
  window: Int,
  acc: List(Float),
) -> List(Float) {
  case list.length(changes) >= window {
    False -> list.reverse(acc)
    True -> {
      let window_changes = list.take(changes, window)
      let autocov = autocovariance(window_changes)
      let roll = 2.0 *. float_sqrt(float.absolute_value(autocov))
      case list.rest(changes) {
        Ok(rest) -> sliding_roll(rest, window, [roll, ..acc])
        Error(_) -> list.reverse([roll, ..acc])
      }
    }
  }
}

// ── Amihud Measure ────────────────────────────────────────────────
// Illiquidity proxy [MICRO]
// Formula: Amihud = (1/W) × Σ|r_i| / (p_i × V_i)

pub fn amihud(
  prices: List(Float),
  volumes: List(Float),
  window window: Int,
) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_period(window))
  let min_len = window + 1
  use _ <- result.try(util.validate_length(prices, min_len))
  use _ <- result.try(util.validate_length(volumes, min_len))

  let returns = compute_returns(prices)
  let vols = case list.rest(volumes) {
    Ok(v) -> v
    Error(_) -> []
  }
  let price_tail = case list.rest(prices) {
    Ok(p) -> p
    Error(_) -> []
  }

  let ratios = compute_amihud_ratios(returns, price_tail, vols)
  Ok(sliding_mean(ratios, window, []))
}

fn compute_amihud_ratios(
  returns: List(Float),
  prices: List(Float),
  volumes: List(Float),
) -> List(Float) {
  case returns, prices, volumes {
    [r, ..rest_r], [p, ..rest_p], [v, ..rest_v] -> {
      let denom = p *. v
      let ratio = case denom >. 0.0 {
        True -> float.absolute_value(r) /. denom
        False -> 0.0
      }
      [ratio, ..compute_amihud_ratios(rest_r, rest_p, rest_v)]
    }
    _, _, _ -> []
  }
}

// ── Helpers ───────────────────────────────────────────────────────

fn compute_changes(prices: List(Float)) -> List(Float) {
  case prices {
    [] | [_] -> []
    [first, ..rest] -> {
      let #(changes, _) =
        list.fold(rest, #([], first), fn(acc, p) {
          let #(cs, prev) = acc
          #([p -. prev, ..cs], p)
        })
      list.reverse(changes)
    }
  }
}

fn compute_returns(prices: List(Float)) -> List(Float) {
  case prices {
    [] | [_] -> []
    [first, ..rest] -> {
      let #(returns, _) =
        list.fold(rest, #([], first), fn(acc, p) {
          let #(rs, prev) = acc
          let ret = case prev >. 0.0 {
            True -> { p -. prev } /. prev
            False -> 0.0
          }
          #([ret, ..rs], p)
        })
      list.reverse(returns)
    }
  }
}

fn autocovariance(changes: List(Float)) -> Float {
  case changes {
    [] | [_] -> 0.0
    [first, ..rest] -> {
      let #(sum, count, _) =
        list.fold(rest, #(0.0, 0, first), fn(acc, c) {
          let #(s, n, prev) = acc
          #(s +. prev *. c, n + 1, c)
        })
      case count > 0 {
        True -> sum /. int_to_float(count)
        False -> 0.0
      }
    }
  }
}

fn sliding_mean(
  values: List(Float),
  window: Int,
  acc: List(Float),
) -> List(Float) {
  case list.length(values) >= window {
    False -> list.reverse(acc)
    True -> {
      let window_vals = list.take(values, window)
      let sum = list.fold(window_vals, 0.0, fn(a, v) { a +. v })
      let mean = sum /. int_to_float(window)
      case list.rest(values) {
        Ok(rest) -> sliding_mean(rest, window, [mean, ..acc])
        Error(_) -> list.reverse([mean, ..acc])
      }
    }
  }
}

fn int_to_float(n: Int) -> Float {
  do_int_to_float(n)
}

@external(erlang, "erlang", "float")
fn do_int_to_float(n: Int) -> Float

fn float_sqrt(x: Float) -> Float {
  case x <=. 0.0 {
    True -> 0.0
    False -> do_sqrt(x)
  }
}

@external(erlang, "math", "sqrt")
fn do_sqrt(x: Float) -> Float
