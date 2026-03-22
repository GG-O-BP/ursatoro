import gleeunit
import ursatoro/candle
import ursatoro/momentum
import ursatoro/util

pub fn main() -> Nil {
  gleeunit.main()
}

// ── Helper ──────────────────────────────────────────────────────────

fn make_candle(close: Float) -> candle.Candle {
  candle.new(open: close, high: close, low: close, close: close, volume: 100.0)
}

fn make_candles(closes: List(Float)) -> List(candle.Candle) {
  case closes {
    [] -> []
    [c, ..rest] -> [make_candle(c), ..make_candles(rest)]
  }
}

fn approx_equal(a: Float, b: Float) -> Bool {
  let diff = case a -. b {
    d if d <. 0.0 -> 0.0 -. d
    d -> d
  }
  diff <. 0.01
}

// ── RSI tests ───────────────────────────────────────────────────────

pub fn rsi_basic_test() {
  let closes = [
    44.0, 44.34, 44.09, 43.61, 44.33, 44.83, 45.1, 45.42, 45.84, 46.08, 45.89,
    46.03, 45.61, 46.28, 46.28,
  ]
  let candles = make_candles(closes)
  let result = momentum.rsi(candles, 14)
  let assert Ok(values) = result
  assert list_length(values) >= 1
  assert all_in_range(values, 0.0, 100.0)
}

pub fn rsi_all_gains_test() {
  let closes = [
    1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0,
    15.0,
  ]
  let candles = make_candles(closes)
  let result = momentum.rsi(candles, 14)
  let assert Ok([rsi_val]) = result
  assert approx_equal(rsi_val, 100.0)
}

pub fn rsi_all_losses_test() {
  let closes = [
    15.0, 14.0, 13.0, 12.0, 11.0, 10.0, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0,
    1.0,
  ]
  let candles = make_candles(closes)
  let result = momentum.rsi(candles, 14)
  let assert Ok([rsi_val]) = result
  assert approx_equal(rsi_val, 0.0)
}

pub fn rsi_insufficient_data_test() {
  let candles = make_candles([1.0, 2.0, 3.0])
  let result = momentum.rsi(candles, 14)
  let assert Error(util.InsufficientData(required: 15, got: 3)) = result
}

pub fn rsi_invalid_period_test() {
  let candles = make_candles([1.0, 2.0])
  let result = momentum.rsi(candles, 0)
  let assert Error(util.InvalidPeriod(0)) = result
}

// ── Stochastic tests ────────────────────────────────────────────────

pub fn stochastic_basic_test() {
  let candles = [
    candle.new(open: 10.0, high: 15.0, low: 8.0, close: 12.0, volume: 100.0),
    candle.new(open: 11.0, high: 16.0, low: 9.0, close: 13.0, volume: 100.0),
    candle.new(open: 12.0, high: 17.0, low: 10.0, close: 14.0, volume: 100.0),
    candle.new(open: 13.0, high: 18.0, low: 11.0, close: 15.0, volume: 100.0),
    candle.new(open: 14.0, high: 19.0, low: 12.0, close: 16.0, volume: 100.0),
  ]
  let result = momentum.stochastic(candles, 3, 2)
  let assert Ok(values) = result
  assert list_length(values) >= 1
  assert all_stochastic_in_range(values)
}

pub fn stochastic_insufficient_data_test() {
  let candles = make_candles([1.0, 2.0])
  let result = momentum.stochastic(candles, 3, 2)
  let assert Error(util.InsufficientData(_, _)) = result
}

pub fn stochastic_invalid_period_test() {
  let candles = make_candles([1.0, 2.0, 3.0])
  let result = momentum.stochastic(candles, 0, 3)
  let assert Error(util.InvalidPeriod(0)) = result
}

// ── Helpers ─────────────────────────────────────────────────────────

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

fn all_in_range(values: List(Float), min: Float, max: Float) -> Bool {
  case values {
    [] -> True
    [v, ..rest] ->
      case v >=. min && v <=. max {
        True -> all_in_range(rest, min, max)
        False -> False
      }
  }
}

fn all_stochastic_in_range(values: List(momentum.StochasticResult)) -> Bool {
  case values {
    [] -> True
    [momentum.StochasticResult(k:, d:), ..rest] ->
      case k >=. 0.0 && k <=. 100.0 && d >=. 0.0 && d <=. 100.0 {
        True -> all_stochastic_in_range(rest)
        False -> False
      }
  }
}
