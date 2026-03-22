import bigdecimal.{type BigDecimal}
import bigdecimal/rounding
import gleam/deque
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import ursatoro/candle.{type Candle}

// ── Error type ──────────────────────────────────────────────────────

pub type IndicatorError {
  InsufficientData(required: Int, got: Int)
  InvalidPeriod(period: Int)
  DivisionByZero
}

// ── Constants ───────────────────────────────────────────────────────

const division_scale = 10

// ── Validation ──────────────────────────────────────────────────────

pub fn validate_period(period: Int) -> Result(Nil, IndicatorError) {
  case period > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidPeriod(period))
  }
}

pub fn validate_length(
  items: List(a),
  required: Int,
) -> Result(Nil, IndicatorError) {
  let got = list.length(items)
  case got >= required {
    True -> Ok(Nil)
    False -> Error(InsufficientData(required:, got:))
  }
}

// ── BigDecimal conversions ──────────────────────────────────────────

pub fn bd_to_float(value: BigDecimal) -> Float {
  let s = bigdecimal.to_plain_string(value)
  case float.parse(s) {
    Ok(f) -> f
    // Integer BigDecimals produce strings without decimal point
    Error(Nil) -> {
      case float.parse(s <> ".0") {
        Ok(f) -> f
        Error(Nil) -> 0.0
      }
    }
  }
}

pub fn bds_to_floats(values: List(BigDecimal)) -> List(Float) {
  list.map(values, bd_to_float)
}

pub fn float_to_bd(value: Float) -> BigDecimal {
  bigdecimal.from_float(value)
}

pub fn int_to_bd(value: Int) -> BigDecimal {
  let s = int.to_string(value)
  case bigdecimal.from_string(s) {
    Ok(bd) -> bd
    Error(Nil) -> bigdecimal.zero()
  }
}

// ── BigDecimal arithmetic helpers ───────────────────────────────────

pub fn safe_divide(
  dividend: BigDecimal,
  divisor: BigDecimal,
) -> Result(BigDecimal, IndicatorError) {
  case bigdecimal.signum(divisor) {
    0 -> Error(DivisionByZero)
    _ -> Ok(bigdecimal.divide(dividend, by: divisor, rounding: rounding.HalfUp))
  }
}

pub fn bd_sum(values: List(BigDecimal)) -> BigDecimal {
  bigdecimal.sum(values)
}

pub fn bd_mean(values: List(BigDecimal)) -> Result(BigDecimal, IndicatorError) {
  case values {
    [] -> Error(DivisionByZero)
    _ -> {
      let sum = bigdecimal.sum(values)
      let count = int_to_bd(list.length(values))
      safe_divide(sum, count)
    }
  }
}

pub fn bd_max(a: BigDecimal, b: BigDecimal) -> BigDecimal {
  case bigdecimal.compare(a, with: b) {
    order.Gt -> a
    order.Eq -> a
    order.Lt -> b
  }
}

pub fn bd_min(a: BigDecimal, b: BigDecimal) -> BigDecimal {
  case bigdecimal.compare(a, with: b) {
    order.Lt -> a
    order.Eq -> a
    order.Gt -> b
  }
}

pub fn bd_abs(value: BigDecimal) -> BigDecimal {
  bigdecimal.absolute_value(value)
}

/// Square root via Newton's method (Babylonian method).
/// Returns zero for zero/negative inputs.
pub fn bd_sqrt(value: BigDecimal) -> BigDecimal {
  let working_scale = division_scale + 4
  case bigdecimal.signum(value) {
    s if s <= 0 -> bigdecimal.zero()
    _ -> {
      let value =
        bigdecimal.rescale(value, scale: working_scale, rounding: rounding.HalfUp)
      let two = int_to_bd(2)
      // Initial guess: value / 2
      let initial =
        bigdecimal.divide(value, by: two, rounding: rounding.HalfUp)
        |> bigdecimal.rescale(scale: working_scale, rounding: rounding.HalfUp)
      newton_sqrt(value, initial, 0)
    }
  }
}

fn newton_sqrt(
  value: BigDecimal,
  guess: BigDecimal,
  iterations: Int,
) -> BigDecimal {
  let working_scale = division_scale + 4
  case iterations >= 50 {
    True ->
      bigdecimal.rescale(
        guess,
        scale: division_scale,
        rounding: rounding.HalfUp,
      )
    False -> {
      let two = int_to_bd(2)
      // next = (guess + value / guess) / 2
      let divided =
        bigdecimal.divide(value, by: guess, rounding: rounding.HalfUp)
        |> bigdecimal.rescale(
          scale: working_scale,
          rounding: rounding.HalfUp,
        )
      let next =
        bigdecimal.divide(
          bigdecimal.add(guess, divided),
          by: two,
          rounding: rounding.HalfUp,
        )
        |> bigdecimal.rescale(
          scale: working_scale,
          rounding: rounding.HalfUp,
        )
      // Check convergence: if |next - guess| is very small, stop
      let diff = bd_abs(bigdecimal.subtract(next, guess))
      let threshold =
        bigdecimal.rescale(
          bigdecimal.one(),
          scale: division_scale + 2,
          rounding: rounding.HalfUp,
        )
      case bigdecimal.compare(diff, with: threshold) {
        order.Lt ->
          bigdecimal.rescale(
            next,
            scale: division_scale,
            rounding: rounding.HalfUp,
          )
        order.Eq ->
          bigdecimal.rescale(
            next,
            scale: division_scale,
            rounding: rounding.HalfUp,
          )
        order.Gt -> newton_sqrt(value, next, iterations + 1)
      }
    }
  }
}

// ── Population standard deviation ───────────────────────────────────

pub fn bd_stddev_population(
  values: List(BigDecimal),
) -> Result(BigDecimal, IndicatorError) {
  use mean <- result.try(bd_mean(values))
  let n = int_to_bd(list.length(values))
  let working_scale = division_scale + 4
  let sum_sq =
    list.fold(values, bigdecimal.zero(), fn(acc, v) {
      let diff = bigdecimal.subtract(v, mean)
      let sq =
        bigdecimal.multiply(diff, diff)
        |> bigdecimal.rescale(
          scale: working_scale,
          rounding: rounding.HalfUp,
        )
      bigdecimal.add(acc, sq)
    })
  use variance <- result.try(safe_divide(sum_sq, n))
  Ok(bd_sqrt(variance))
}

// ── Sliding window SMA ──────────────────────────────────────────────

pub fn sma_values(
  values: List(BigDecimal),
  period: Int,
) -> Result(List(BigDecimal), IndicatorError) {
  use _ <- result.try(validate_period(period))
  use _ <- result.try(validate_length(values, period))
  let period_bd = int_to_bd(period)
  let #(results, _, _, _) =
    list.fold(values, #([], deque.new(), bigdecimal.zero(), 0), fn(acc, value) {
      let #(results, window, window_sum, count) = acc
      let new_window = deque.push_back(window, value)
      let new_sum = bigdecimal.add(window_sum, value)
      let new_count = count + 1
      case new_count > period {
        True -> {
          case deque.pop_front(new_window) {
            Ok(#(oldest, trimmed_window)) -> {
              let trimmed_sum = bigdecimal.subtract(new_sum, oldest)
              let sma =
                bigdecimal.divide(
                  trimmed_sum,
                  by: period_bd,
                  rounding: rounding.HalfUp,
                )
              #([sma, ..results], trimmed_window, trimmed_sum, period)
            }
            Error(Nil) -> #(results, new_window, new_sum, new_count)
          }
        }
        False ->
          case new_count == period {
            True -> {
              let sma =
                bigdecimal.divide(
                  new_sum,
                  by: period_bd,
                  rounding: rounding.HalfUp,
                )
              #([sma, ..results], new_window, new_sum, new_count)
            }
            False -> #(results, new_window, new_sum, new_count)
          }
      }
    })
  Ok(list.reverse(results))
}

// ── True Range ──────────────────────────────────────────────────────

pub fn true_range(prev: Candle, current: Candle) -> BigDecimal {
  let high_low = bigdecimal.subtract(candle.high(current), candle.low(current))
  let high_prev_close =
    bd_abs(bigdecimal.subtract(candle.high(current), candle.close(prev)))
  let low_prev_close =
    bd_abs(bigdecimal.subtract(candle.low(current), candle.close(prev)))
  high_low |> bd_max(high_prev_close) |> bd_max(low_prev_close)
}

// ── Hundred constant ────────────────────────────────────────────────

pub fn hundred() -> BigDecimal {
  int_to_bd(100)
}
