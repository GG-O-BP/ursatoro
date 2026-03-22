// Kalman filter for price smoothing. [Paper: LOB - Crypto LOB Dynamics]
// "Data preprocessing > model complexity; Kalman suitable for real-time streaming"
//
// State transition: x_t = x_{t-1} + w_{t-1}, w ~ N(0, Q)
// Observation:      v_t = x_t + ε_t,         ε ~ N(0, R)
// Kalman gain:      K_t = (P_{t-1} + Q) / (P_{t-1} + Q + R)
// Posterior:        x̂_t = x̂_{t-1} + K_t(v_t - x̂_{t-1})
// Error covariance: P_t = (1 - K_t)(P_{t-1} + Q)

import gleam/list
import gleam/result
import ursatoro/util.{type IndicatorError}

// ── Types ─────────────────────────────────────────────────────────

pub type KalmanState {
  KalmanState(estimate: Float, error_cov: Float)
}

// ── Streaming API ─────────────────────────────────────────────────

pub fn kalman_new(initial_price: Float) -> KalmanState {
  KalmanState(estimate: initial_price, error_cov: 1.0)
}

pub fn kalman_update(
  state: KalmanState,
  observation: Float,
  q: Float,
  r: Float,
) -> KalmanState {
  let predicted_cov = state.error_cov +. q
  let kalman_gain = predicted_cov /. { predicted_cov +. r }
  let new_estimate =
    state.estimate +. kalman_gain *. { observation -. state.estimate }
  let new_error_cov = { 1.0 -. kalman_gain } *. predicted_cov
  KalmanState(estimate: new_estimate, error_cov: new_error_cov)
}

// ── Batch API ─────────────────────────────────────────────────────

pub fn kalman_smooth(
  prices: List(Float),
  q: Float,
  r: Float,
) -> Result(List(Float), IndicatorError) {
  use _ <- result.try(util.validate_length(prices, 1))
  case prices {
    [] -> Ok([])
    [first, ..rest] -> {
      let initial = kalman_new(first)
      let #(results, _) =
        list.fold(rest, #([first], initial), fn(acc, price) {
          let #(estimates, state) = acc
          let new_state = kalman_update(state, price, q, r)
          #([new_state.estimate, ..estimates], new_state)
        })
      Ok(list.reverse(results))
    }
  }
}
