# ursatoro

[![Package Version](https://img.shields.io/hexpm/v/ursatoro)](https://hex.pm/packages/ursatoro)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/ursatoro/)

Gleam trading technical indicators library. Pure functions that take OHLCV candle data and return computed indicator values.

The brain of a trading signal bot — equivalent to Python's TA-Lib/pandas-ta, but for the Gleam ecosystem.

## Install

```sh
gleam add ursatoro@1
```

## Indicators

| Category | Function | Description |
|----------|----------|-------------|
| Trend | `sma` | Simple Moving Average |
| Trend | `ema` | Exponential Moving Average |
| Trend | `macd` | Moving Average Convergence Divergence → `MacdResult` |
| Momentum | `rsi` | Relative Strength Index (Wilder's smoothing) |
| Momentum | `stochastic` | Stochastic Oscillator (%K, %D) → `StochasticResult` |
| Momentum | `momentum_factor` | Rolling momentum via log returns |
| Volatility | `bollinger_bands` | Bollinger Bands (upper, middle, lower) → `BollingerBandsResult` |
| Volatility | `atr` | Average True Range (Wilder's smoothing) |
| Volatility | `har_volatility` | HAR volatility model (daily/weekly/monthly) → `HarResult` |
| Volume | `vwap` | Volume Weighted Average Price |
| Volume | `obv` | On-Balance Volume |
| Filter | `kalman_new` | Initialize Kalman filter state → `KalmanState` |
| Filter | `kalman_update` | Update Kalman state with new observation → `KalmanState` |
| Filter | `kalman_smooth` | Batch Kalman smoothing over price series |
| Microstructure | `vpin` | Volume-Synchronized Probability of Informed Trading |
| Microstructure | `roll_measure` | Roll measure (liquidity proxy) |
| Microstructure | `amihud` | Amihud illiquidity measure |

## Usage

```gleam
import ursatoro

pub fn main() {
  let candles = [
    ursatoro.candle(open: 10.0, high: 12.0, low: 9.0, close: 11.0, volume: 1000.0),
    ursatoro.candle(open: 11.0, high: 13.0, low: 10.0, close: 12.0, volume: 1500.0),
    ursatoro.candle(open: 12.0, high: 14.0, low: 11.0, close: 13.0, volume: 2000.0),
    ursatoro.candle(open: 13.0, high: 15.0, low: 12.0, close: 14.0, volume: 1800.0),
    ursatoro.candle(open: 14.0, high: 16.0, low: 13.0, close: 15.0, volume: 2200.0),
  ]

  // Simple Moving Average (period 3)
  let assert Ok(sma_values) = ursatoro.sma(candles, period: 3)

  // Exponential Moving Average (period 3)
  let assert Ok(ema_values) = ursatoro.ema(candles, period: 3)

  // MACD (fast 12, slow 26, signal 9)
  let assert Ok(macd_values) = ursatoro.macd(candles, fast: 12, slow: 26, signal: 9)

  // RSI (period 14) — needs at least period + 1 candles
  let assert Ok(rsi_values) = ursatoro.rsi(candles, period: 14)

  // Stochastic Oscillator (%K period 14, %D period 3)
  let assert Ok(stoch_values) = ursatoro.stochastic(candles, k_period: 14, d_period: 3)

  // Bollinger Bands (period 20, 2 standard deviations)
  let assert Ok(bb_values) = ursatoro.bollinger_bands(candles, period: 20, num_std: 2.0)

  // Average True Range (period 14)
  let assert Ok(atr_values) = ursatoro.atr(candles, period: 14)

  // VWAP
  let assert Ok(vwap_values) = ursatoro.vwap(candles)

  // OBV
  let assert Ok(obv_values) = ursatoro.obv(candles)

  // Momentum factor (30-day rolling)
  let assert Ok(mom_values) = ursatoro.momentum_factor(candles, window: 30)

  // HAR volatility model
  let assert Ok(har_values) = ursatoro.har_volatility(candles, daily: 1, weekly: 5, monthly: 22)

  // Kalman filter — batch smoothing
  let prices = [10.0, 11.0, 12.0, 13.0, 14.0]
  let assert Ok(smoothed) = ursatoro.kalman_smooth(prices, 0.01, 1.0)

  // Kalman filter — streaming
  let state = ursatoro.kalman_new(10.0)
  let state = ursatoro.kalman_update(state, 11.0, 0.01, 1.0)

  // VPIN (requires TradeBar list)
  let trade_bars = [ursatoro.TradeBar(buy_volume: 100.0, sell_volume: 50.0, total_volume: 150.0, price_change: 0.5)]
  let assert Ok(vpin_values) = ursatoro.vpin(trade_bars, window: 10)

  // Roll measure (liquidity proxy)
  let assert Ok(roll_values) = ursatoro.roll_measure(prices, window: 3)

  // Amihud illiquidity
  let volumes = [1000.0, 1500.0, 2000.0, 1800.0, 2200.0]
  let assert Ok(amihud_values) = ursatoro.amihud(prices, volumes, window: 3)
}
```

## Error Handling

All indicator functions return `Result(List(value), IndicatorError)`. Possible errors:

- `InsufficientData(required, got)` — not enough candles for the given period
- `InvalidPeriod(period)` — period must be > 0
- `DivisionByZero` — unexpected zero divisor

```gleam
import ursatoro

case ursatoro.sma(candles, period: 20) {
  Ok(values) -> // use values
  Error(ursatoro.InsufficientData(required, got)) -> // handle
  Error(ursatoro.InvalidPeriod(period)) -> // handle
  Error(ursatoro.DivisionByZero) -> // handle
}
```

## Precision

All internal calculations use `bigdecimal` for arbitrary-precision decimal arithmetic. Float values are only produced at the API boundary. This prevents floating-point drift in financial calculations.

## Development

```sh
gleam build   # Build the project
gleam test    # Run the tests
gleam format src test  # Format code
```

## License

[Blue Oak Model License 1.0.0](LICENSE)
