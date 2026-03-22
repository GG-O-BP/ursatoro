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
| Trend | `macd` | Moving Average Convergence Divergence |
| Momentum | `rsi` | Relative Strength Index (Wilder's smoothing) |
| Momentum | `stochastic` | Stochastic Oscillator (%K, %D) |
| Volatility | `bollinger_bands` | Bollinger Bands (upper, middle, lower) |
| Volatility | `atr` | Average True Range (Wilder's smoothing) |
| Volume | `vwap` | Volume Weighted Average Price |
| Volume | `obv` | On-Balance Volume |

## Usage

```gleam
import ursatoro
import ursatoro/candle

pub fn main() {
  let candles = [
    candle.new(open: 10.0, high: 12.0, low: 9.0, close: 11.0, volume: 1000.0),
    candle.new(open: 11.0, high: 13.0, low: 10.0, close: 12.0, volume: 1500.0),
    candle.new(open: 12.0, high: 14.0, low: 11.0, close: 13.0, volume: 2000.0),
    candle.new(open: 13.0, high: 15.0, low: 12.0, close: 14.0, volume: 1800.0),
    candle.new(open: 14.0, high: 16.0, low: 13.0, close: 15.0, volume: 2200.0),
  ]

  // Simple Moving Average (period 3)
  let assert Ok(sma_values) = ursatoro.sma(candles, period: 3)

  // RSI (period 14) — needs at least 15 candles
  let assert Ok(rsi_values) = ursatoro.rsi(candles, period: 14)

  // Bollinger Bands (period 20, 2 standard deviations)
  let assert Ok(bb_values) = ursatoro.bollinger_bands(candles, period: 20, num_std: 2.0)

  // MACD (fast 12, slow 26, signal 9)
  let assert Ok(macd_values) = ursatoro.macd(candles, fast: 12, slow: 26, signal: 9)

  // VWAP
  let assert Ok(vwap_values) = ursatoro.vwap(candles)

  // OBV
  let assert Ok(obv_values) = ursatoro.obv(candles)
}
```

## Error Handling

All indicator functions return `Result(List(value), IndicatorError)`. Possible errors:

- `InsufficientData(required, got)` — not enough candles for the given period
- `InvalidPeriod(period)` — period must be > 0
- `DivisionByZero` — unexpected zero divisor

```gleam
import ursatoro
import ursatoro/util

case ursatoro.sma(candles, period: 20) {
  Ok(values) -> // use values
  Error(util.InsufficientData(required, got)) -> // handle
  Error(util.InvalidPeriod(period)) -> // handle
  Error(util.DivisionByZero) -> // handle
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
