import bigdecimal
import bigdecimal/rounding
import gleam/list
import gleam/order
import gleam/result
import ursatoro/candle.{type Candle}
import ursatoro/util.{type IndicatorError}

// ── VWAP ────────────────────────────────────────────────────────────

pub fn vwap(candles: List(Candle)) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_length(candles, 1))
  let three = util.int_to_bd(3)
  let #(results, _, _) =
    list.fold(candles, #([], bigdecimal.zero(), bigdecimal.zero()), fn(acc, c) {
      let #(results, cum_tp_vol, cum_vol) = acc
      // Typical price = (high + low + close) / 3
      let tp =
        bigdecimal.divide(
          bigdecimal.add(
            bigdecimal.add(candle.high(c), candle.low(c)),
            candle.close(c),
          ),
          by: three,
          rounding: rounding.HalfUp,
        )
      let tp_vol = bigdecimal.multiply(tp, candle.volume(c))
      let new_cum_tp_vol = bigdecimal.add(cum_tp_vol, tp_vol)
      let new_cum_vol = bigdecimal.add(cum_vol, candle.volume(c))
      // VWAP = cumulative(tp * vol) / cumulative(vol)
      let vwap_val = case bigdecimal.signum(new_cum_vol) {
        0 -> bigdecimal.zero()
        _ ->
          bigdecimal.divide(
            new_cum_tp_vol,
            by: new_cum_vol,
            rounding: rounding.HalfUp,
          )
      }
      #([vwap_val, ..results], new_cum_tp_vol, new_cum_vol)
    })
  Ok(list.reverse(results) |> util.bds_to_floats)
}

// ── OBV ─────────────────────────────────────────────────────────────

pub fn obv(candles: List(Candle)) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_length(candles, 1))
  case candles {
    [] -> Ok([])
    [first, ..rest] -> {
      let #(results, _, _) =
        list.fold(
          rest,
          #([bigdecimal.zero()], bigdecimal.zero(), first),
          fn(acc, c) {
            let #(results, prev_obv, prev_candle) = acc
            let new_obv = case
              bigdecimal.compare(
                candle.close(c),
                with: candle.close(prev_candle),
              )
            {
              order.Gt -> bigdecimal.add(prev_obv, candle.volume(c))
              order.Lt -> bigdecimal.subtract(prev_obv, candle.volume(c))
              order.Eq -> prev_obv
            }
            #([new_obv, ..results], new_obv, c)
          },
        )
      Ok(list.reverse(results) |> util.bds_to_floats)
    }
  }
}
