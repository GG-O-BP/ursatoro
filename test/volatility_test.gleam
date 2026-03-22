import gleeunit
import ursatoro/candle
import ursatoro/util
import ursatoro/volatility

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

// ── Bollinger Bands tests ───────────────────────────────────────────

pub fn bollinger_basic_test() {
  let candles = make_candles([10.0, 10.0, 10.0, 10.0, 10.0])
  let result = volatility.bollinger_bands(candles, 3, 2.0)
  let assert Ok(values) = result
  assert list_length(values) == 3
  let assert [
    volatility.BollingerBandsResult(upper: u1, middle: m1, lower: l1),
    ..
  ] = values
  assert approx_equal(m1, 10.0)
  assert approx_equal(u1, 10.0)
  assert approx_equal(l1, 10.0)
}

pub fn bollinger_with_variance_test() {
  let candles = make_candles([1.0, 2.0, 3.0])
  let result = volatility.bollinger_bands(candles, 3, 2.0)
  let assert Ok([volatility.BollingerBandsResult(upper: u, middle: m, lower: l)]) =
    result
  assert approx_equal(m, 2.0)
  assert u >. m
  assert l <. m
}

pub fn bollinger_insufficient_data_test() {
  let candles = make_candles([1.0, 2.0])
  let result = volatility.bollinger_bands(candles, 3, 2.0)
  let assert Error(util.InsufficientData(required: 3, got: 2)) = result
}

pub fn bollinger_invalid_period_test() {
  let candles = make_candles([1.0, 2.0, 3.0])
  let result = volatility.bollinger_bands(candles, 0, 2.0)
  let assert Error(util.InvalidPeriod(0)) = result
}

// ── ATR tests ───────────────────────────────────────────────────────

pub fn atr_basic_test() {
  let candles = [
    candle.new(open: 10.0, high: 12.0, low: 9.0, close: 11.0, volume: 100.0),
    candle.new(open: 11.0, high: 13.0, low: 10.0, close: 12.0, volume: 100.0),
    candle.new(open: 12.0, high: 14.0, low: 11.0, close: 13.0, volume: 100.0),
    candle.new(open: 13.0, high: 15.0, low: 12.0, close: 14.0, volume: 100.0),
  ]
  let result = volatility.atr(candles, 2)
  let assert Ok(values) = result
  assert list_length(values) >= 1
  assert all_positive(values)
}

pub fn atr_insufficient_data_test() {
  let candles = make_candles([1.0, 2.0])
  let result = volatility.atr(candles, 3)
  let assert Error(util.InsufficientData(required: 4, got: 2)) = result
}

pub fn atr_invalid_period_test() {
  let candles = make_candles([1.0, 2.0, 3.0])
  let result = volatility.atr(candles, 0)
  let assert Error(util.InvalidPeriod(0)) = result
}

pub fn atr_flat_prices_test() {
  let candles = [
    candle.new(open: 10.0, high: 10.0, low: 10.0, close: 10.0, volume: 100.0),
    candle.new(open: 10.0, high: 10.0, low: 10.0, close: 10.0, volume: 100.0),
    candle.new(open: 10.0, high: 10.0, low: 10.0, close: 10.0, volume: 100.0),
  ]
  let result = volatility.atr(candles, 2)
  let assert Ok(values) = result
  assert all_zero(values)
}

// ── Helpers ─────────────────────────────────────────────────────────

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

fn all_positive(values: List(Float)) -> Bool {
  case values {
    [] -> True
    [v, ..rest] ->
      case v >=. 0.0 {
        True -> all_positive(rest)
        False -> False
      }
  }
}

fn all_zero(values: List(Float)) -> Bool {
  case values {
    [] -> True
    [v, ..rest] ->
      case v <. 0.001 && v >. -0.001 {
        True -> all_zero(rest)
        False -> False
      }
  }
}
