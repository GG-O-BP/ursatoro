import ursatoro/candle.{type Candle}
import ursatoro/filter
import ursatoro/microstructure
import ursatoro/momentum
import ursatoro/trend
import ursatoro/util
import ursatoro/volatility
import ursatoro/volume

pub type IndicatorError =
  util.IndicatorError

// ── Candle re-export ────────────────────────────────────────────────

pub fn candle(
  open open: Float,
  high high: Float,
  low low: Float,
  close close: Float,
  volume volume: Float,
) -> Candle {
  candle.new(open:, high:, low:, close:, volume:)
}

// ── Trend indicators ────────────────────────────────────────────────

pub fn sma(
  candles: List(Candle),
  period period: Int,
) -> Result(List(Float), IndicatorError) {
  trend.sma(candles, period)
}

pub fn ema(
  candles: List(Candle),
  period period: Int,
) -> Result(List(Float), IndicatorError) {
  trend.ema(candles, period)
}

pub fn macd(
  candles: List(Candle),
  fast fast: Int,
  slow slow: Int,
  signal signal: Int,
) -> Result(List(trend.MacdResult), IndicatorError) {
  trend.macd(candles, fast, slow, signal)
}

// ── Momentum indicators ─────────────────────────────────────────────

pub fn rsi(
  candles: List(Candle),
  period period: Int,
) -> Result(List(Float), IndicatorError) {
  momentum.rsi(candles, period)
}

pub fn stochastic(
  candles: List(Candle),
  k_period k_period: Int,
  d_period d_period: Int,
) -> Result(List(momentum.StochasticResult), IndicatorError) {
  momentum.stochastic(candles, k_period, d_period)
}

// ── Volatility indicators ───────────────────────────────────────────

pub fn bollinger_bands(
  candles: List(Candle),
  period period: Int,
  num_std num_std: Float,
) -> Result(List(volatility.BollingerBandsResult), IndicatorError) {
  volatility.bollinger_bands(candles, period, num_std)
}

pub fn atr(
  candles: List(Candle),
  period period: Int,
) -> Result(List(Float), IndicatorError) {
  volatility.atr(candles, period)
}

// ── Volume indicators ───────────────────────────────────────────────

pub fn vwap(candles: List(Candle)) -> Result(List(Float), IndicatorError) {
  volume.vwap(candles)
}

pub fn obv(candles: List(Candle)) -> Result(List(Float), IndicatorError) {
  volume.obv(candles)
}

// ── Filter indicators (data preprocessing) ────────────────────────
// [Paper: LOB - Crypto LOB Dynamics]

pub type KalmanState =
  filter.KalmanState

pub fn kalman_new(initial_price: Float) -> KalmanState {
  filter.kalman_new(initial_price)
}

pub fn kalman_update(
  state: KalmanState,
  observation: Float,
  q: Float,
  r: Float,
) -> KalmanState {
  filter.kalman_update(state, observation, q, r)
}

pub fn kalman_smooth(
  prices: List(Float),
  q: Float,
  r: Float,
) -> Result(List(Float), IndicatorError) {
  filter.kalman_smooth(prices, q, r)
}

// ── Microstructure indicators ─────────────────────────────────────
// [Paper: MICRO - Microstructure & Market Dynamics]

pub type TradeBar =
  microstructure.TradeBar

pub fn vpin(
  trade_bars: List(TradeBar),
  window window: Int,
) -> Result(List(Float), IndicatorError) {
  microstructure.vpin(trade_bars, window:)
}

pub fn roll_measure(
  prices: List(Float),
  window window: Int,
) -> Result(List(Float), IndicatorError) {
  microstructure.roll_measure(prices, window:)
}

pub fn amihud(
  prices: List(Float),
  volumes: List(Float),
  window window: Int,
) -> Result(List(Float), IndicatorError) {
  microstructure.amihud(prices, volumes, window:)
}

// ── Momentum factor ───────────────────────────────────────────────
// [Paper: QA - Quantitative Alpha in Crypto]

pub fn momentum_factor(
  candles: List(Candle),
  window window: Int,
) -> Result(List(Float), IndicatorError) {
  momentum.momentum_factor(candles, window:)
}

// ── HAR Volatility ────────────────────────────────────────────────
// [Paper: QA - Quantitative Alpha in Crypto]

pub type HarResult =
  volatility.HarResult

pub fn har_volatility(
  candles: List(Candle),
  daily daily: Int,
  weekly weekly: Int,
  monthly monthly: Int,
) -> Result(List(HarResult), IndicatorError) {
  volatility.har_volatility(candles, daily:, weekly:, monthly:)
}
