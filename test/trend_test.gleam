import gleeunit
import ursatoro/candle
import ursatoro/trend
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
  diff <. 0.0001
}

// ── SMA tests ───────────────────────────────────────────────────────

pub fn sma_basic_test() {
  let candles = make_candles([1.0, 2.0, 3.0, 4.0, 5.0])
  let result = trend.sma(candles, 3)
  // SMA(3): [2.0, 3.0, 4.0]
  let assert Ok(values) = result
  let assert [v1, v2, v3] = values
  assert approx_equal(v1, 2.0)
  assert approx_equal(v2, 3.0)
  assert approx_equal(v3, 4.0)
}

pub fn sma_exact_boundary_test() {
  let candles = make_candles([10.0, 20.0, 30.0])
  let result = trend.sma(candles, 3)
  let assert Ok([value]) = result
  assert approx_equal(value, 20.0)
}

pub fn sma_insufficient_data_test() {
  let candles = make_candles([1.0, 2.0])
  let result = trend.sma(candles, 3)
  let assert Error(util.InsufficientData(required: 3, got: 2)) = result
}

pub fn sma_invalid_period_test() {
  let candles = make_candles([1.0, 2.0, 3.0])
  let result = trend.sma(candles, 0)
  let assert Error(util.InvalidPeriod(0)) = result
}

pub fn sma_empty_list_test() {
  let result = trend.sma([], 3)
  let assert Error(util.InsufficientData(required: 3, got: 0)) = result
}

pub fn sma_single_candle_period_one_test() {
  let candles = make_candles([42.0])
  let result = trend.sma(candles, 1)
  let assert Ok([value]) = result
  assert approx_equal(value, 42.0)
}

// ── EMA tests ───────────────────────────────────────────────────────

pub fn ema_basic_test() {
  // 5 values, period 3. First EMA = SMA(1,2,3) = 2.0
  // k = 2/(3+1) = 0.5
  // EMA(4) = 4*0.5 + 2.0*0.5 = 3.0
  // EMA(5) = 5*0.5 + 3.0*0.5 = 4.0
  let candles = make_candles([1.0, 2.0, 3.0, 4.0, 5.0])
  let result = trend.ema(candles, 3)
  let assert Ok(values) = result
  assert list_length(values) == 3
  let assert [v1, v2, v3] = values
  assert approx_equal(v1, 2.0)
  assert approx_equal(v2, 3.0)
  assert approx_equal(v3, 4.0)
}

pub fn ema_insufficient_data_test() {
  let candles = make_candles([1.0])
  let result = trend.ema(candles, 3)
  let assert Error(util.InsufficientData(required: 3, got: 1)) = result
}

pub fn ema_single_period_test() {
  let candles = make_candles([5.0, 10.0, 15.0])
  let result = trend.ema(candles, 1)
  let assert Ok(values) = result
  assert list_length(values) == 3
}

// ── MACD tests ──────────────────────────────────────────────────────

pub fn macd_basic_test() {
  let closes = generate_ascending(40, 100.0, 1.0)
  let candles = make_candles(closes)
  let result = trend.macd(candles, 12, 26, 9)
  let assert Ok(values) = result
  assert list_length(values) > 0
}

pub fn macd_insufficient_data_test() {
  let candles = make_candles([1.0, 2.0, 3.0])
  let result = trend.macd(candles, 12, 26, 9)
  let assert Error(util.InsufficientData(_, _)) = result
}

pub fn macd_invalid_period_test() {
  let candles = make_candles([1.0, 2.0, 3.0])
  let result = trend.macd(candles, 0, 26, 9)
  let assert Error(util.InvalidPeriod(0)) = result
}

// ── Helpers ─────────────────────────────────────────────────────────

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

fn generate_ascending(count: Int, start: Float, step: Float) -> List(Float) {
  generate_ascending_loop(count, start, step, [])
}

fn generate_ascending_loop(
  count: Int,
  current: Float,
  step: Float,
  acc: List(Float),
) -> List(Float) {
  case count <= 0 {
    True -> reverse(acc)
    False ->
      generate_ascending_loop(count - 1, current +. step, step, [current, ..acc])
  }
}

fn reverse(items: List(a)) -> List(a) {
  reverse_loop(items, [])
}

fn reverse_loop(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [first, ..rest] -> reverse_loop(rest, [first, ..acc])
  }
}
