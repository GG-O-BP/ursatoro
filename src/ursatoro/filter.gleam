// Filters for price smoothing. [Paper: LOB - Crypto LOB Dynamics]
// "Data preprocessing > model complexity" — LOB paper found Savitzky-Golay
// smoothing (cubic, window 21) mattered more than architecture.
//
// Kalman filter: real-time streaming smoothing.
// Savitzky-Golay: batch polynomial smoothing with noise removal.

import gleam/int
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

// ── Savitzky-Golay Filter [LOB: cubic d=3, window=21] ──────────
// Polynomial smoothing via convolution coefficients.
// Preserves peaks and edges better than simple moving average.

pub fn savitzky_golay(
  prices: List(Float),
  window_length window_length: Int,
  polyorder polyorder: Int,
) -> Result(List(Float), IndicatorError) {
  let n = list.length(prices)
  // Validate: window must be odd, polyorder < window, enough data
  case window_length % 2 == 1 && window_length >= 3 {
    False -> Error(util.InvalidPeriod(window_length))
    True ->
      case polyorder >= 0 && polyorder < window_length {
        False -> Error(util.InvalidPeriod(polyorder))
        True ->
          case n >= window_length {
            False ->
              Error(util.InsufficientData(required: window_length, got: n))
            True -> {
              let half = window_length / 2
              let coeffs = sg_coefficients(half, polyorder)
              let arr = list.index_map(prices, fn(p, i) { #(i, p) })
              let prices_arr = prices
              let smoothed =
                list.map(arr, fn(entry) {
                  let #(i, _) = entry
                  case i < half || i >= n - half {
                    // Edge: keep original value
                    True -> get_at(prices_arr, i)
                    // Interior: apply convolution
                    False -> apply_coeffs(prices_arr, coeffs, i, half)
                  }
                })
              Ok(smoothed)
            }
          }
      }
  }
}

// Compute SG convolution coefficients for the smoothing (0th derivative).
// Uses the Gram polynomial approach for numerical stability.
// Returns List(Float) of length (2*half+1), symmetric for 0th derivative.
fn sg_coefficients(half: Int, polyorder: Int) -> List(Float) {
  // Build Vandermonde-like system and solve for row 0 of pseudo-inverse.
  // For each position j in -half..half, coefficient = Σ_k gram_poly(j,k) * gram_poly(0,k) * (2k+1) / (2*half+1)
  let m = int_to_float(2 * half + 1)
  int.range(from: -half, to: half, with: [], run: fn(acc, j) {
    let jf = int_to_float(j)
    let hf = int_to_float(half)
    [compute_sg_coeff(jf, hf, polyorder, m), ..acc]
  })
  |> list.reverse
}

// Compute single SG coefficient using Gram polynomial expansion.
fn compute_sg_coeff(j: Float, half: Float, order: Int, m: Float) -> Float {
  int.range(from: 0, to: order, with: 0.0, run: fn(acc, k) {
    let gj = gram_poly(j, half, k)
    let g0 = gram_poly(0.0, half, k)
    let kf = int_to_float(k)
    let weight = { 2.0 *. kf +. 1.0 } /. m
    acc +. gj *. g0 *. weight
  })
}

// Gram polynomial P_k(j) over [-half, half], orthogonal basis.
// P_0(j) = 1
// P_1(j) = j / half  (scaled)
// P_k(j) = ((2k-1)*j*P_{k-1}(j) - (k-1)*(half^2 - (k-1)^2/(4))*P_{k-2}(j)) / (k * half)
// Simplified: use direct recursive evaluation.
fn gram_poly(j: Float, half: Float, order: Int) -> Float {
  case order {
    0 -> 1.0
    1 -> j /. half
    k -> {
      let kf = int_to_float(k)
      let km1 = int_to_float(k - 1)
      let p_prev = gram_poly(j, half, k - 1)
      let p_prev2 = gram_poly(j, half, k - 2)
      let num1 = { 2.0 *. kf -. 1.0 } *. j *. p_prev
      let num2 =
        km1 *. { half *. half -. { km1 *. km1 -. 1.0 } /. 4.0 } *. p_prev2
      { num1 -. num2 } /. { kf *. half }
    }
  }
}

// Apply convolution coefficients at position i.
fn apply_coeffs(
  prices: List(Float),
  coeffs: List(Float),
  center: Int,
  half: Int,
) -> Float {
  let start = center - half
  list.index_fold(coeffs, 0.0, fn(acc, coeff, idx) {
    let price = get_at(prices, start + idx)
    acc +. coeff *. price
  })
}

// Get element at index from list (0-based). Returns 0.0 if out of bounds.
fn get_at(lst: List(Float), idx: Int) -> Float {
  case idx < 0 {
    True -> 0.0
    False ->
      case list.drop(lst, idx) {
        [val, ..] -> val
        [] -> 0.0
      }
  }
}

@external(erlang, "erlang", "float")
fn int_to_float(n: Int) -> Float
