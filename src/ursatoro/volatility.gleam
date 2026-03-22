import bigdecimal.{type BigDecimal}
import bigdecimal/rounding
import gleam/deque
import gleam/list
import gleam/result
import ursatoro/candle.{type Candle}
import ursatoro/util.{type IndicatorError}

// ── Bollinger Bands result type ─────────────────────────────────────

pub type BollingerBandsResult {
  BollingerBandsResult(upper: Float, middle: Float, lower: Float)
}

// ── Bollinger Bands ─────────────────────────────────────────────────

pub fn bollinger_bands(
  candles: List(Candle),
  period: Int,
  num_std: Float,
) -> Result(List(BollingerBandsResult), IndicatorError) {
  use _ <- result.try(util.validate_period(period))
  use _ <- result.try(util.validate_length(candles, period))
  let closes = list.map(candles, candle.close)
  let num_std_bd = util.float_to_bd(num_std)
  // Sliding window: compute SMA and stddev for each window position
  let #(results, _, _) =
    list.fold(closes, #([], deque.new(), 0), fn(acc, value) {
      let #(results, window, count) = acc
      let new_window = deque.push_back(window, value)
      let new_count = count + 1
      case new_count > period {
        True -> {
          case deque.pop_front(new_window) {
            Ok(#(_, trimmed)) -> {
              let bb = compute_bb(trimmed, num_std_bd)
              #([bb, ..results], trimmed, period)
            }
            Error(Nil) -> #(results, new_window, new_count)
          }
        }
        False ->
          case new_count == period {
            True -> {
              let bb = compute_bb(new_window, num_std_bd)
              #([bb, ..results], new_window, new_count)
            }
            False -> #(results, new_window, new_count)
          }
      }
    })
  Ok(list.reverse(results))
}

fn compute_bb(
  window: deque.Deque(BigDecimal),
  num_std: BigDecimal,
) -> BollingerBandsResult {
  let values = deque.to_list(window)
  // Compute mean (SMA)
  let middle = case util.bd_mean(values) {
    Ok(m) -> m
    Error(_) -> bigdecimal.zero()
  }
  // Compute population stddev
  let stddev = case util.bd_stddev_population(values) {
    Ok(s) -> s
    Error(_) -> bigdecimal.zero()
  }
  let band_width = bigdecimal.multiply(num_std, stddev)
  let upper = bigdecimal.add(middle, band_width)
  let lower = bigdecimal.subtract(middle, band_width)
  BollingerBandsResult(
    upper: util.bd_to_float(upper),
    middle: util.bd_to_float(middle),
    lower: util.bd_to_float(lower),
  )
}

// ── ATR ─────────────────────────────────────────────────────────────

pub fn atr(
  candles: List(Candle),
  period: Int,
) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_period(period))
  // Need period + 1 candles (true range needs previous candle)
  use _ <- result.try(util.validate_length(candles, period + 1))
  // Compute true ranges from pairs of consecutive candles
  let true_ranges = compute_true_ranges(candles)
  // First ATR = SMA of first `period` true ranges
  let initial_trs = list.take(true_ranges, period)
  use first_atr <- result.try(util.bd_mean(initial_trs))
  let remaining_trs = list.drop(true_ranges, period)
  let period_bd = util.int_to_bd(period)
  let period_minus_one = util.int_to_bd(period - 1)
  // Wilder's smoothing
  let #(results, _) =
    list.fold(remaining_trs, #([first_atr], first_atr), fn(acc, tr) {
      let #(results, prev_atr) = acc
      // ATR = (prev_atr * (period-1) + current_tr) / period
      let new_atr =
        bigdecimal.divide(
          bigdecimal.add(bigdecimal.multiply(prev_atr, period_minus_one), tr),
          by: period_bd,
          rounding: rounding.HalfUp,
        )
      #([new_atr, ..results], new_atr)
    })
  Ok(list.reverse(results) |> util.bds_to_floats)
}

fn compute_true_ranges(candles: List(Candle)) -> List(BigDecimal) {
  case candles {
    [] -> []
    [_] -> []
    [first, ..rest] -> {
      let #(trs, _) =
        list.fold(rest, #([], first), fn(acc, current) {
          let #(trs, prev) = acc
          let tr = util.true_range(prev, current)
          #([tr, ..trs], current)
        })
      list.reverse(trs)
    }
  }
}

// ── HAR Volatility Model ──────────────────────────────────────────
// [Paper: QA - Quantitative Alpha in Crypto]
// "HAR model comparable to LightGBM/LSTM, simple and interpretable"
// σ²_{t+1} = β_d × σ²_t + β_w × σ²_{t:t-4} + β_m × σ²_{t:t-21}
// β_d=0.4, β_w=0.3, β_m=0.3

pub type HarResult {
  HarResult(
    predicted_vol: Float,
    daily_vol: Float,
    weekly_vol: Float,
    monthly_vol: Float,
  )
}

pub fn har_volatility(
  candles: List(Candle),
  daily daily: Int,
  weekly weekly: Int,
  monthly monthly: Int,
) -> Result(List(HarResult), IndicatorError) {
  use _ <- result.try(util.validate_period(daily))
  use _ <- result.try(util.validate_period(weekly))
  use _ <- result.try(util.validate_period(monthly))
  let min_len = monthly + 1
  use _ <- result.try(util.validate_length(candles, min_len))

  // Compute log returns
  let closes = list.map(candles, fn(c) { util.bd_to_float(candle.close(c)) })
  let log_returns = compute_log_returns_float(closes)

  // Compute HAR predictions for each valid position
  Ok(compute_har_series(log_returns, daily, weekly, monthly, []))
}

fn compute_har_series(
  returns: List(Float),
  daily: Int,
  weekly: Int,
  monthly: Int,
  acc: List(HarResult),
) -> List(HarResult) {
  case list.length(returns) >= monthly {
    False -> list.reverse(acc)
    True -> {
      let d_vol = realized_variance(list.take(returns, daily))
      let w_vol = realized_variance(list.take(returns, weekly))
      let m_vol = realized_variance(list.take(returns, monthly))
      // HAR prediction: β_d=0.4, β_w=0.3, β_m=0.3
      let predicted = 0.4 *. d_vol +. 0.3 *. w_vol +. 0.3 *. m_vol
      let result =
        HarResult(
          predicted_vol: predicted,
          daily_vol: d_vol,
          weekly_vol: w_vol,
          monthly_vol: m_vol,
        )
      case list.rest(returns) {
        Ok(rest) ->
          compute_har_series(rest, daily, weekly, monthly, [result, ..acc])
        Error(_) -> list.reverse([result, ..acc])
      }
    }
  }
}

fn realized_variance(returns: List(Float)) -> Float {
  let n = list.length(returns)
  case n > 0 {
    False -> 0.0
    True -> {
      let n_f = do_int_to_float(n)
      let mean = list.fold(returns, 0.0, fn(acc, r) { acc +. r }) /. n_f
      let sum_sq =
        list.fold(returns, 0.0, fn(acc, r) {
          let diff = r -. mean
          acc +. diff *. diff
        })
      sum_sq /. n_f
    }
  }
}

fn compute_log_returns_float(prices: List(Float)) -> List(Float) {
  case prices {
    [] | [_] -> []
    [first, ..rest] -> {
      let #(returns, _) =
        list.fold(rest, #([], first), fn(acc, p) {
          let #(rs, prev) = acc
          let ret = case prev >. 0.0 {
            True -> do_log(p /. prev)
            False -> 0.0
          }
          #([ret, ..rs], p)
        })
      list.reverse(returns)
    }
  }
}

@external(erlang, "erlang", "float")
fn do_int_to_float(n: Int) -> Float

@external(erlang, "math", "log")
fn do_log(x: Float) -> Float
