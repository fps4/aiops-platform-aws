"""Pure statistical anomaly detection algorithms.

All functions operate on plain numpy/pandas objects — no AWS SDK imports —
so they are easy to unit test without any mocking.
"""
import numpy as np
import pandas as pd

try:
    import ruptures as rpt
    _RUPTURES_AVAILABLE = True
except ImportError:  # pragma: no cover
    _RUPTURES_AVAILABLE = False

try:
    from statsmodels.tsa.seasonal import STL
    _STATSMODELS_AVAILABLE = True
except ImportError:  # pragma: no cover
    _STATSMODELS_AVAILABLE = False

# Sensitivity → Z-score threshold mapping
SENSITIVITY_THRESHOLDS: dict[str, float] = {
    "low": 4.0,
    "medium": 3.0,
    "high": 2.0,
}


# ─── STL decomposition ────────────────────────────────────────────────────────

def stl_decompose(
    series: pd.Series,
    period: int = 288,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Decompose a time series into trend, seasonal, and residual components.

    Uses STL (Seasonal and Trend decomposition using Loess).

    Args:
        series: Time-indexed pandas Series. Must have at least ``2 * period``
                data points for meaningful decomposition.
        period: Seasonality period in samples. Default is 288 (5-minute samples
                over a 24-hour day).

    Returns:
        Tuple of (trend, seasonal, residual) as numpy arrays.
    """
    if not _STATSMODELS_AVAILABLE:
        raise ImportError("statsmodels is required for STL decomposition")

    if len(series) < 2 * period:
        # Fall back to simple mean-centred residuals when not enough data
        trend = np.full(len(series), series.mean())
        seasonal = np.zeros(len(series))
        residual = series.values - trend
        return trend, seasonal, residual

    stl = STL(series, period=period, robust=True)
    result = stl.fit()
    return result.trend, result.seasonal, result.resid


# ─── PELT changepoint detection ───────────────────────────────────────────────

def pelt_changepoints(
    series: np.ndarray,
    model: str = "rbf",
    penalty: float = 10.0,
) -> list[int]:
    """Detect changepoints using the PELT algorithm (ruptures library).

    Args:
        series: 1-D numpy array of metric values.
        model: Cost model for ruptures (``"rbf"`` or ``"l2"``).
        penalty: Penalty value controlling the number of changepoints detected.
                 Higher values → fewer changepoints.

    Returns:
        List of sample indices where changepoints were detected (exclusive end
        indices as returned by ruptures, minus the final end-of-series marker).
    """
    if not _RUPTURES_AVAILABLE:
        raise ImportError("ruptures is required for PELT changepoint detection")

    if len(series) < 4:
        return []

    signal = series.reshape(-1, 1) if series.ndim == 1 else series
    algo = rpt.Pelt(model=model).fit(signal)
    result = algo.predict(pen=penalty)
    # ruptures always appends len(series) as the final marker; exclude it
    return result[:-1]


# ─── Z-score ──────────────────────────────────────────────────────────────────

def z_score(current: float, residual: np.ndarray) -> float:
    """Compute the Z-score of *current* relative to a residual distribution.

    Args:
        current: The observation to score.
        residual: Historical residual values used to estimate mean and std.

    Returns:
        Z-score. Positive values indicate upward deviations.
    """
    if len(residual) == 0:
        return 0.0

    mu = float(np.mean(residual))
    sigma = float(np.std(residual, ddof=1)) if len(residual) > 1 else 0.0

    if sigma == 0:
        return 0.0

    return (current - mu) / sigma


# ─── EWMA ─────────────────────────────────────────────────────────────────────

def ewma_score(series: np.ndarray, span: int = 12) -> float:
    """Compute an Exponentially Weighted Moving Average anomaly score.

    The score is the Z-score of the final observation relative to the EWMA
    residuals over the provided window.

    Args:
        series: 1-D array of metric values (chronological order).
        span: EWMA span (half-life equivalent).

    Returns:
        Anomaly score for the last data point.
    """
    if len(series) < 2:
        return 0.0

    s = pd.Series(series, dtype=float)
    ewma = s.ewm(span=span, adjust=False).mean()
    residuals = (s - ewma).values[:-1]  # exclude last point to avoid look-ahead
    current_residual = float((s - ewma).values[-1])

    return z_score(current_residual, residuals)


# ─── Anomaly classifier ───────────────────────────────────────────────────────

def is_anomaly(z: float, sensitivity: str = "medium") -> bool:
    """Classify a Z-score as anomalous based on sensitivity level.

    Args:
        z: Absolute Z-score (sign ignored; both spikes and drops detected).
        sensitivity: One of ``"low"`` (4σ), ``"medium"`` (3σ), ``"high"`` (2σ).

    Returns:
        True if ``abs(z)`` exceeds the sensitivity threshold.
    """
    threshold = SENSITIVITY_THRESHOLDS.get(sensitivity, SENSITIVITY_THRESHOLDS["medium"])
    return abs(z) >= threshold
