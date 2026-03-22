import bigdecimal.{type BigDecimal}
import bigdecimal/rounding
import gleam/deque
import gleam/list
import gleam/result
import ursatoro/candle.{type Candle}
import ursatoro/util.{type IndicatorError}

// ── Stochastic result type ──────────────────────────────────────────

pub type StochasticResult {
  StochasticResult(k: Float, d: Float)
}

// ── RSI ─────────────────────────────────────────────────────────────

pub fn rsi(
  candles: List(Candle),
  period: Int,
) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_period(period))
  // Need period + 1 candles (period changes require period+1 prices)
  use _ <- result.try(util.validate_length(candles, period + 1))
  let closes = list.map(candles, candle.close)
  // Compute price changes
  let changes = compute_changes(closes)
  // Split gains and losses
  let gains_losses = list.map(changes, split_gain_loss)
  let gains = list.map(gains_losses, fn(gl) { gl.0 })
  let losses = list.map(gains_losses, fn(gl) { gl.1 })
  // First avg_gain and avg_loss: SMA of first `period` values
  let initial_gains = list.take(gains, period)
  let initial_losses = list.take(losses, period)
  use first_avg_gain <- result.try(util.bd_mean(initial_gains))
  use first_avg_loss <- result.try(util.bd_mean(initial_losses))
  let remaining_gains = list.drop(gains, period)
  let remaining_losses = list.drop(losses, period)
  // Compute first RSI
  let first_rsi = compute_rsi_value(first_avg_gain, first_avg_loss)
  let period_bd = util.int_to_bd(period)
  let period_minus_one = util.int_to_bd(period - 1)
  // Wilder's smoothing over remaining values
  let remaining =
    list.map2(remaining_gains, remaining_losses, fn(g, l) { #(g, l) })
  let #(results, _, _) =
    list.fold(
      remaining,
      #([first_rsi], first_avg_gain, first_avg_loss),
      fn(acc, gl) {
        let #(results, prev_avg_gain, prev_avg_loss) = acc
        let #(gain, loss) = gl
        // Wilder's smoothing: avg = (prev * (period-1) + current) / period
        let new_avg_gain =
          bigdecimal.divide(
            bigdecimal.add(
              bigdecimal.multiply(prev_avg_gain, period_minus_one),
              gain,
            ),
            by: period_bd,
            rounding: rounding.HalfUp,
          )
        let new_avg_loss =
          bigdecimal.divide(
            bigdecimal.add(
              bigdecimal.multiply(prev_avg_loss, period_minus_one),
              loss,
            ),
            by: period_bd,
            rounding: rounding.HalfUp,
          )
        let rsi_val = compute_rsi_value(new_avg_gain, new_avg_loss)
        #([rsi_val, ..results], new_avg_gain, new_avg_loss)
      },
    )
  Ok(list.reverse(results) |> util.bds_to_floats)
}

fn compute_changes(closes: List(BigDecimal)) -> List(BigDecimal) {
  case closes {
    [] -> []
    [_] -> []
    [first, ..rest] -> {
      let #(changes, _) =
        list.fold(rest, #([], first), fn(acc, close) {
          let #(changes, prev) = acc
          let change = bigdecimal.subtract(close, prev)
          #([change, ..changes], close)
        })
      list.reverse(changes)
    }
  }
}

fn split_gain_loss(change: BigDecimal) -> #(BigDecimal, BigDecimal) {
  case bigdecimal.signum(change) {
    s if s > 0 -> #(change, bigdecimal.zero())
    s if s < 0 -> #(bigdecimal.zero(), bigdecimal.absolute_value(change))
    _ -> #(bigdecimal.zero(), bigdecimal.zero())
  }
}

fn compute_rsi_value(avg_gain: BigDecimal, avg_loss: BigDecimal) -> BigDecimal {
  let hundred = util.hundred()
  case bigdecimal.signum(avg_loss) {
    0 ->
      // No losses: RSI = 100
      hundred
    _ -> {
      let rs =
        bigdecimal.divide(avg_gain, by: avg_loss, rounding: rounding.HalfUp)
      // RSI = 100 - 100 / (1 + RS)
      let one_plus_rs = bigdecimal.add(bigdecimal.one(), rs)
      let ratio =
        bigdecimal.divide(hundred, by: one_plus_rs, rounding: rounding.HalfUp)
      bigdecimal.subtract(hundred, ratio)
    }
  }
}

// ── Stochastic ──────────────────────────────────────────────────────

pub fn stochastic(
  candles: List(Candle),
  k_period: Int,
  d_period: Int,
) -> Result(List(StochasticResult), IndicatorError) {
  use _ <- result.try(util.validate_period(k_period))
  use _ <- result.try(util.validate_period(d_period))
  // Need k_period candles for first %K, plus d_period - 1 more for first %D
  use _ <- result.try(util.validate_length(candles, k_period + d_period - 1))
  // Compute %K values using sliding window
  let k_values = compute_k_values(candles, k_period)
  // Compute %D = SMA of %K values
  use d_values <- result.try(util.sma_values(k_values, d_period))
  // Align %K to %D length
  let k_len = list.length(k_values)
  let d_len = list.length(d_values)
  let k_offset = k_len - d_len
  let aligned_k = list.drop(k_values, k_offset)
  // Build results
  let results =
    list.map2(aligned_k, d_values, fn(k, d) {
      StochasticResult(k: util.bd_to_float(k), d: util.bd_to_float(d))
    })
  Ok(results)
}

fn compute_k_values(candles: List(Candle), k_period: Int) -> List(BigDecimal) {
  let hundred = util.hundred()
  let #(results, _, _) =
    list.fold(candles, #([], deque.new(), 0), fn(acc, c) {
      let #(results, window, count) = acc
      let new_window = deque.push_back(window, c)
      let new_count = count + 1
      case new_count > k_period {
        True -> {
          case deque.pop_front(new_window) {
            Ok(#(_, trimmed)) -> {
              let k = k_from_window(trimmed, c, hundred)
              #([k, ..results], trimmed, k_period)
            }
            Error(Nil) -> #(results, new_window, new_count)
          }
        }
        False ->
          case new_count == k_period {
            True -> {
              let k = k_from_window(new_window, c, hundred)
              #([k, ..results], new_window, new_count)
            }
            False -> #(results, new_window, new_count)
          }
      }
    })
  list.reverse(results)
}

fn k_from_window(
  window: deque.Deque(Candle),
  current: Candle,
  hundred: BigDecimal,
) -> BigDecimal {
  let window_list = deque.to_list(window)
  let highs = list.map(window_list, candle.high)
  let lows = list.map(window_list, candle.low)
  let highest_high = list_max_bd(highs)
  let lowest_low = list_min_bd(lows)
  let range = bigdecimal.subtract(highest_high, lowest_low)
  case bigdecimal.signum(range) {
    0 -> bigdecimal.zero()
    _ -> {
      let numerator = bigdecimal.subtract(candle.close(current), lowest_low)
      bigdecimal.multiply(
        bigdecimal.divide(numerator, by: range, rounding: rounding.HalfUp),
        hundred,
      )
    }
  }
}

fn list_max_bd(values: List(BigDecimal)) -> BigDecimal {
  case values {
    [] -> bigdecimal.zero()
    [first, ..rest] -> list.fold(rest, first, util.bd_max)
  }
}

fn list_min_bd(values: List(BigDecimal)) -> BigDecimal {
  case values {
    [] -> bigdecimal.zero()
    [first, ..rest] -> list.fold(rest, first, util.bd_min)
  }
}

// ── Momentum Factor ─────────────────────────────────────────────────
// [Paper: QA - Quantitative Alpha in Crypto]
// "30-day rolling momentum, core of Liu-Tsyvinski-Wu 3-factor model"
// Formula: momentum = Σ ln(close_i / close_{i-1}) over window
// Output length: n - window

pub fn momentum_factor(
  candles: List(Candle),
  window window: Int,
) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_period(window))
  let min_len = window + 1
  use _ <- result.try(util.validate_length(candles, min_len))

  // Extract close prices as Float (need ln which BigDecimal doesn't support)
  let closes = list.map(candles, fn(c) { util.bd_to_float(candle.close(c)) })

  // Compute log returns
  let log_returns = compute_log_returns(closes)

  // Sliding window sum
  Ok(sliding_sum(log_returns, window, []))
}

fn compute_log_returns(prices: List(Float)) -> List(Float) {
  case prices {
    [] | [_] -> []
    [first, ..rest] -> {
      let #(returns, _) =
        list.fold(rest, #([], first), fn(acc, p) {
          let #(rs, prev) = acc
          let ret = case prev >. 0.0 {
            True -> do_log(p /. prev)
            False -> 0.0
          }
          #([ret, ..rs], p)
        })
      list.reverse(returns)
    }
  }
}

fn sliding_sum(
  values: List(Float),
  window: Int,
  acc: List(Float),
) -> List(Float) {
  case list.length(values) >= window {
    False -> list.reverse(acc)
    True -> {
      let window_vals = list.take(values, window)
      let sum = list.fold(window_vals, 0.0, fn(a, v) { a +. v })
      case list.rest(values) {
        Ok(rest) -> sliding_sum(rest, window, [sum, ..acc])
        Error(_) -> list.reverse([sum, ..acc])
      }
    }
  }
}

@external(erlang, "math", "log")
fn do_log(x: Float) -> Float
