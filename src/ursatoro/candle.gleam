import bigdecimal.{type BigDecimal}

pub opaque type Candle {
  Candle(
    open: BigDecimal,
    high: BigDecimal,
    low: BigDecimal,
    close: BigDecimal,
    volume: BigDecimal,
  )
}

pub fn new(
  open open: Float,
  high high: Float,
  low low: Float,
  close close: Float,
  volume volume: Float,
) -> Candle {
  Candle(
    open: bigdecimal.from_float(open),
    high: bigdecimal.from_float(high),
    low: bigdecimal.from_float(low),
    close: bigdecimal.from_float(close),
    volume: bigdecimal.from_float(volume),
  )
}

pub fn open(candle: Candle) -> BigDecimal {
  candle.open
}

pub fn high(candle: Candle) -> BigDecimal {
  candle.high
}

pub fn low(candle: Candle) -> BigDecimal {
  candle.low
}

pub fn close(candle: Candle) -> BigDecimal {
  candle.close
}

pub fn volume(candle: Candle) -> BigDecimal {
  candle.volume
}
