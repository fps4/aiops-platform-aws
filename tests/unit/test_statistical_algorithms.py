"""Unit tests for statistical detection algorithms (no AWS dependencies)."""
import numpy as np
import pandas as pd
import pytest

from src.detection.statistical.algorithms import (
    SENSITIVITY_THRESHOLDS,
    ewma_score,
    is_anomaly,
    pelt_changepoints,
    stl_decompose,
    z_score,
)


# ─── z_score ──────────────────────────────────────────────────────────────────

class TestZScore:
    def test_z_score_detects_spike(self, sample_metrics_series):
        """A value 20σ above the baseline must produce a very high Z-score."""
        baseline = sample_metrics_series[:-1]
        current = float(sample_metrics_series[-1])  # the spike (200)
        residuals = baseline - baseline.mean()
        result = z_score(current, residuals)
        assert result > 10, f"Expected z > 10 for clear spike, got {result}"

    def test_z_score_normal_variation_ignored(self, normal_metrics_series):
        """Small variation within the normal range should yield |z| < 3."""
        # Use the last point as current; rest as residuals
        data = normal_metrics_series
        residuals = data[:-1] - data[:-1].mean()
        current_residual = float(data[-1] - data[:-1].mean())
        result = z_score(current_residual, residuals)
        assert abs(result) < 3, f"Expected |z| < 3 for normal variation, got {result}"

    def test_z_score_zero_std_returns_zero(self):
        """When residuals have zero variance the z-score is 0."""
        residuals = np.ones(10) * 5.0
        result = z_score(5.0, residuals)
        assert result == 0.0

    def test_z_score_empty_residuals_returns_zero(self):
        result = z_score(100.0, np.array([]))
        assert result == 0.0

    def test_z_score_negative_deviation(self):
        """Downward deviations produce negative Z-scores."""
        rng = np.random.default_rng(0)
        residuals = rng.normal(0, 1, 1000)
        result = z_score(-10.0, residuals)
        assert result < -5


# ─── ewma_score ───────────────────────────────────────────────────────────────

class TestEwmaScore:
    def test_ewma_tracks_trend(self):
        """EWMA score increases when the last point is elevated."""
        rng = np.random.default_rng(1)
        baseline = rng.normal(100, 5, 100)
        elevated = np.append(baseline, [200.0])
        score = ewma_score(elevated)
        assert score > 3, f"Expected elevated EWMA score, got {score}"

    def test_ewma_normal_series_low_score(self):
        """EWMA score is small for stationary series."""
        rng = np.random.default_rng(2)
        series = rng.normal(0, 1, 200)
        score = ewma_score(series)
        assert abs(score) < 5, f"Expected low EWMA score for normal series, got {score}"

    def test_ewma_single_point_returns_zero(self):
        assert ewma_score(np.array([42.0])) == 0.0

    def test_ewma_two_points_does_not_raise(self):
        result = ewma_score(np.array([1.0, 2.0]))
        assert isinstance(result, float)


# ─── stl_decompose ────────────────────────────────────────────────────────────

class TestStlDecompose:
    def test_stl_decomposes_seasonal_pattern(self):
        """Seasonal component should be non-trivial for a synthetic periodic signal."""
        n = 600  # more than 2 × period=288, but use period=12 for speed
        period = 12
        t = np.arange(n)
        seasonal_signal = np.sin(2 * np.pi * t / period)
        trend_signal = 0.01 * t
        noise = np.random.default_rng(3).normal(0, 0.1, n)
        series = pd.Series(trend_signal + seasonal_signal + noise)

        trend, seasonal, residual = stl_decompose(series, period=period)

        # Seasonal component must have meaningful amplitude (not all zeros)
        assert np.std(seasonal) > 0.1, "Seasonal component should have variance"
        # Residuals should be small relative to the signal
        assert np.std(residual) < 1.0, "Residuals should be smaller than seasonal amplitude"

    def test_stl_insufficient_data_falls_back(self):
        """When series is shorter than 2 × period, fall back without error."""
        series = pd.Series(np.ones(10))
        trend, seasonal, residual = stl_decompose(series, period=288)
        assert len(trend) == 10
        assert len(seasonal) == 10
        assert len(residual) == 10
        # All seasonal values should be zero in fall-back
        assert np.all(seasonal == 0)

    def test_stl_returns_three_arrays(self, sample_metrics_series):
        series = pd.Series(sample_metrics_series[:600])
        result = stl_decompose(series, period=12)
        assert len(result) == 3
        for arr in result:
            assert len(arr) == 600


# ─── pelt_changepoints ────────────────────────────────────────────────────────

class TestPeltChangepoints:
    def test_pelt_detects_single_changepoint(self):
        """A step-function signal should yield exactly one changepoint."""
        rng = np.random.default_rng(4)
        segment1 = rng.normal(0, 1, 100)
        segment2 = rng.normal(10, 1, 100)  # clear shift in mean
        signal = np.concatenate([segment1, segment2])

        cps = pelt_changepoints(signal, model="l2", penalty=5.0)

        assert len(cps) >= 1, "Should detect at least one changepoint"
        # Changepoint should be close to index 100
        assert any(80 <= cp <= 120 for cp in cps), f"Changepoint not near expected position: {cps}"

    def test_pelt_stationary_series_no_changepoints(self):
        """A stationary series should have no changepoints (or very few)."""
        rng = np.random.default_rng(5)
        signal = rng.normal(0, 1, 200)
        cps = pelt_changepoints(signal, model="rbf", penalty=20.0)
        assert len(cps) <= 1, f"Expected ≤1 changepoint in stationary series, got {cps}"

    def test_pelt_short_series_returns_empty(self):
        result = pelt_changepoints(np.array([1.0, 2.0, 3.0]))
        assert result == []

    def test_pelt_multiple_changepoints_detected(self):
        """Three distinct segments should produce two changepoints."""
        rng = np.random.default_rng(6)
        s1 = rng.normal(0, 0.5, 50)
        s2 = rng.normal(10, 0.5, 50)
        s3 = rng.normal(5, 0.5, 50)
        signal = np.concatenate([s1, s2, s3])
        cps = pelt_changepoints(signal, model="l2", penalty=2.0)
        assert len(cps) >= 2


# ─── is_anomaly ───────────────────────────────────────────────────────────────

class TestIsAnomaly:
    @pytest.mark.parametrize("sensitivity,threshold", [
        ("low", 4.0),
        ("medium", 3.0),
        ("high", 2.0),
    ])
    def test_is_anomaly_sensitivity_thresholds(self, sensitivity, threshold):
        """Verify exact σ thresholds for each sensitivity level."""
        assert SENSITIVITY_THRESHOLDS[sensitivity] == threshold

        # Just below threshold → not anomaly
        assert not is_anomaly(threshold - 0.01, sensitivity)
        # At threshold → anomaly
        assert is_anomaly(threshold, sensitivity)
        # Above threshold → anomaly
        assert is_anomaly(threshold + 1.0, sensitivity)

    def test_is_anomaly_negative_z_uses_absolute_value(self):
        """Drops (negative Z-scores) should also be classified as anomalies."""
        assert is_anomaly(-3.5, "medium")

    def test_is_anomaly_unknown_sensitivity_uses_medium(self):
        """Unknown sensitivity should fall back to medium (3σ)."""
        assert is_anomaly(3.5, "unknown_level")
        assert not is_anomaly(2.5, "unknown_level")

    def test_empty_series_handled_gracefully(self):
        """z_score on empty residuals should not raise and is_anomaly should work."""
        z = z_score(999.0, np.array([]))
        assert isinstance(z, float)
        result = is_anomaly(z, "high")
        assert isinstance(result, bool)
