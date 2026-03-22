import gleeunit
import ursatoro/candle
import ursatoro/util
import ursatoro/volume

pub fn main() -> Nil {
  gleeunit.main()
}

// ── Helper ──────────────────────────────────────────────────────────

fn approx_equal(a: Float, b: Float) -> Bool {
  let diff = case a -. b {
    d if d <. 0.0 -> 0.0 -. d
    d -> d
  }
  diff <. 0.01
}

// ── VWAP tests ──────────────────────────────────────────────────────

pub fn vwap_basic_test() {
  let candles = [
    candle.new(open: 10.0, high: 10.0, low: 10.0, close: 10.0, volume: 100.0),
    candle.new(open: 10.0, high: 10.0, low: 10.0, close: 10.0, volume: 200.0),
  ]
  let result = volume.vwap(candles)
  let assert Ok([v1, v2]) = result
  assert approx_equal(v1, 10.0)
  assert approx_equal(v2, 10.0)
}

pub fn vwap_weighted_test() {
  // Candle 1: tp = (12+8+10)/3 = 10.0, vol = 100
  // Candle 2: tp = (22+18+20)/3 = 20.0, vol = 300
  // VWAP after candle 2: (10*100 + 20*300) / (100+300) = 7000/400 = 17.5
  let candles = [
    candle.new(open: 10.0, high: 12.0, low: 8.0, close: 10.0, volume: 100.0),
    candle.new(open: 20.0, high: 22.0, low: 18.0, close: 20.0, volume: 300.0),
  ]
  let result = volume.vwap(candles)
  let assert Ok([v1, v2]) = result
  assert approx_equal(v1, 10.0)
  assert approx_equal(v2, 17.5)
}

pub fn vwap_single_candle_test() {
  let candles = [
    candle.new(open: 50.0, high: 55.0, low: 45.0, close: 50.0, volume: 1000.0),
  ]
  let result = volume.vwap(candles)
  let assert Ok([v]) = result
  assert approx_equal(v, 50.0)
}

pub fn vwap_empty_test() {
  let result = volume.vwap([])
  let assert Error(util.InsufficientData(required: 1, got: 0)) = result
}

// ── OBV tests ───────────────────────────────────────────────────────

pub fn obv_basic_test() {
  // Close: 10 -> 12 (up, +200) -> 11 (down, -300) -> 13 (up, +400)
  // OBV:   0  -> 200 -> -100 -> 300
  let candles = [
    candle.new(open: 10.0, high: 11.0, low: 9.0, close: 10.0, volume: 100.0),
    candle.new(open: 11.0, high: 13.0, low: 10.0, close: 12.0, volume: 200.0),
    candle.new(open: 12.0, high: 12.0, low: 10.0, close: 11.0, volume: 300.0),
    candle.new(open: 11.0, high: 14.0, low: 11.0, close: 13.0, volume: 400.0),
  ]
  let result = volume.obv(candles)
  let assert Ok([v1, v2, v3, v4]) = result
  assert approx_equal(v1, 0.0)
  assert approx_equal(v2, 200.0)
  assert approx_equal(v3, -100.0)
  assert approx_equal(v4, 300.0)
}

pub fn obv_flat_prices_test() {
  let candles = [
    candle.new(open: 10.0, high: 10.0, low: 10.0, close: 10.0, volume: 100.0),
    candle.new(open: 10.0, high: 10.0, low: 10.0, close: 10.0, volume: 200.0),
    candle.new(open: 10.0, high: 10.0, low: 10.0, close: 10.0, volume: 300.0),
  ]
  let result = volume.obv(candles)
  let assert Ok([v1, v2, v3]) = result
  assert approx_equal(v1, 0.0)
  assert approx_equal(v2, 0.0)
  assert approx_equal(v3, 0.0)
}

pub fn obv_empty_test() {
  let result = volume.obv([])
  let assert Error(util.InsufficientData(required: 1, got: 0)) = result
}
